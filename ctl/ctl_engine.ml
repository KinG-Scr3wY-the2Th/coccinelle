(* **********************************************************************
 *
 * Implementation of a Witness Tree model checking engine for CTL-FVex 
 * 
 *
 * $Id$
 *
 * **********************************************************************)

(* ********************************************************************** *)
(* Module: SUBST (substitutions: meta. vars and values)                   *)
(* ********************************************************************** *)

module type SUBST =
  sig
    type value
    type mvar
    val eq_mvar: mvar -> mvar -> bool
    val eq_val: value -> value -> bool
    val merge_val: value -> value -> value
    val print_mvar : mvar -> unit
    val print_value : value -> unit
  end
;;

(* ********************************************************************** *)
(* Module: GRAPH (control flow graphs / model)                            *)
(* ********************************************************************** *)

module type GRAPH =
  sig
    type node
    type cfg
    val predecessors: cfg -> node -> node list
    val print_node : node -> unit
  end
;;

module OGRAPHEXT_GRAPH = 
  struct
    type node = int;;
    type cfg = (string,unit) Ograph_extended.ograph_extended;;
    let predecessors cfg n = List.map fst ((cfg#predecessors n)#tolist);;
    let print_node i = Format.print_string (Common.i_to_s i)
  end
;;


(* ********************************************************************** *)


exception TODO_CTL            (* implementation still not quite done so... *)
exception NEVER_CTL			(* Some things should never happen *)

(* ---------------------------------------------------------------------- *)
(* Misc. useful generic functions                                         *)
(* ---------------------------------------------------------------------- *)

(* Sanity-preserving definitions *)
let itos i = string_of_int i;;

let head = List.hd

let tail l = 
  match l with
    [] -> []
  | (x::xs) -> xs
;;

let foldl = List.fold_left;;

let foldl1 f xs = foldl f (head xs) (tail xs)

let foldr = List.fold_right;;

let rec scanl f q xs = 
  q :: (match xs with
	  | []      -> []
	  | (x::xs) -> scanl f (f q x) xs)
;;

let scanl1 f xs =
  match xs with
    | []      -> []
    | (x::xs) -> scanl f x xs
;;

let rec mapAccumL f s xs =
  match xs with
    | []      -> (s,[])
    | (x::xs) -> 
	let (s',y) = f s x in
	let (s'',ys) = mapAccumL f s' xs in
	  (s'',y::ys)
;;

let append = List.append;;

let concat = List.concat;;

let map = List.map;;

let filter = List.filter;;

let partition = List.partition;;

let concatmap f l = List.concat (List.map f l);;

let maybe f g opt =
  match opt with
    | None -> g
    | Some x -> f x
;;

let some_map f opts = map (maybe (fun x -> Some (f x)) None) opts

let some_tolist_alt opts = concatmap (maybe (fun x -> [x]) []) opts

let rec some_tolist opts =
  match opts with
    | []             -> []
    | (Some x)::rest -> x::(some_tolist rest)
    | _::rest        -> some_tolist rest 
;;

let rec groupBy eq l =
    match l with
      [] -> []
    | (x::xs) -> 
	let (xs1,xs2) = partition (fun x' -> eq x x') xs in
	(x::xs1)::(groupBy eq xs2)
;;

let group l = groupBy (=) l;;

let rec memBy eq x l =
  match l with
    [] -> false
  | (y::ys) -> if (eq x y) then true else (memBy eq x ys)
;;

(* FIX ME: rename *)
let rec nubBy eq ls =
  match ls with
    [] -> []
  | (x::xs) when (memBy eq x xs) -> nubBy eq xs
  | (x::xs) -> x::(nubBy eq xs)
;;

(* FIX ME: rename *)
let rec nub ls = nubBy (=) ls

let setifyBy eq xs = List.sort compare (nubBy eq xs);;

let setify xs = List.sort compare (nub xs);;

let unionBy eq xs ys =
  let rec preunion xs ys =
    match (xs,ys) with
      ([],ys') -> ys'
    | (xs',[]) -> xs'
    | (x::xs',y::ys') when eq x y -> x::(preunion xs' ys')
    | (x::xs',y::ys') when not (eq x y) -> x::(preunion xs' (y::ys')) 
    |  _ -> raise NEVER_CTL
  in
  setifyBy eq (nubBy eq (preunion xs ys))
;;

let union xs ys = setify (unionBy (=) xs ys);;

let setdiff xs ys = setify (filter (fun x -> not (List.mem x ys)) xs);;

let subseteqBy eq xs ys = List.for_all (fun x -> memBy eq x ys) xs;;

let subseteq xs ys = List.for_all (fun x -> List.mem x ys) xs;;

let setequalBy eq xs ys = (subseteqBy eq xs ys) & (subseteqBy eq ys xs);;

let setequal xs ys = (subseteq xs ys) & (subseteq ys xs);;

let subset xs ys = 
  (subseteq xs ys) & (List.length (nub xs) < List.length (nub ys));;

(* Fix point calculation *)
let rec fix eq f x =
  let x' = f x in if (eq x x') then x' else fix eq f x'
;;

(* Fix point calculation on set-valued functions *)
let setfix f x = setify (fix setequal f x);;

let rec allpairs f l1 l2 = foldr (fun x -> append (map (f x) l2)) l1 [];;

let lmerge f m l1 l2 =
  let mrg x1 x2 = if (f x1 x2) then [m x1 x2] else []
  in concat (allpairs mrg l1 l2)
;;


(* ********************************************************************** *)
(* Module: CTL_ENGINE                                                     *)
(* ********************************************************************** *)

module CTL_ENGINE =
  functor (SUB : SUBST) -> 
    functor (G : GRAPH) ->
struct


open Ast_ctl

type ('state,'subst,'anno) generic_triple = 
    'state * 'subst * ('state,'subst,'anno) generic_witnesstree;;

type ('state,'subst,'anno) generic_algo = 
    ('state,'subst,'anno) generic_triple list;;


let (print_generic_subst: (SUB.mvar, SUB.value) Ast_ctl.generic_subst -> unit) = fun subst ->
  match subst with
  | Subst (mvar, value) -> 
      Format.print_string ("+");
      SUB.print_mvar mvar; 
      Format.print_string " --> ";
      SUB.print_value value
  | NegSubst (mvar, value) -> 
      Format.print_string ("-");
      SUB.print_mvar mvar; 
      Format.print_string " --> ";
      SUB.print_value value

let (print_generic_substitution:  (SUB.mvar, SUB.value) Ast_ctl.generic_substitution -> unit) = fun substxs ->
  begin
    Format.print_string "[";
    Common.print_between (fun () -> Format.print_string ";" ) print_generic_subst substxs;
    Format.print_string "]";
  end

let rec (print_generic_witness: (G.node, (SUB.mvar, SUB.value) Ast_ctl.generic_substitution, 'anno) 
           Ast_ctl.generic_witness -> unit) = function
  | Wit (state, subst, anno, childrens) -> 
      Format.print_string "wit ";
      G.print_node state;
      print_generic_substitution subst;
      (* go in children ? *)
  | NegWit  (state, subst, anno, childrens) -> 
      Format.print_string "wit ";
      G.print_node state;
      print_generic_substitution subst;
      (* go in children ? *)

and (print_generic_witnesstree: (G.node, (SUB.mvar, SUB.value) Ast_ctl.generic_substitution, 'anno) 
       Ast_ctl.generic_witnesstree -> unit) = fun witnesstree ->
  begin
    Format.print_string "{";
    Common.print_between (fun () -> Format.print_string ";" ) print_generic_witness witnesstree;
    Format.print_string "}";
  end


and (print_generic_triple: (G.node * 
                            (SUB.mvar, SUB.value) Ast_ctl.generic_substitution *
                            (G.node, (SUB.mvar, SUB.value) Ast_ctl.generic_substitution, 'b list) Ast_ctl.generic_witnesstree)
                         -> unit) = fun (node, subst, tree) -> 
  begin
    G.print_node node;
    print_generic_substitution subst;
    print_generic_witnesstree tree;
  end

and (print_generic_algo: (G.node * 
                         (SUB.mvar, SUB.value) Ast_ctl.generic_substitution *
                         (G.node, (SUB.mvar, SUB.value) Ast_ctl.generic_substitution, 'b list) Ast_ctl.generic_witnesstree)
                         list -> unit) = fun xs -> 
  begin
    Format.print_string "<";
    Common.print_between (fun () -> Format.print_string ";" ) print_generic_triple xs;
    Format.print_string ">";
  end




(* ---------------------------------------------------------------------- *)
(*                                                                        *)
(* ---------------------------------------------------------------------- *)

(* FIX ME: optimise under assumption that xs and ys are sorted *)
let conflictBy conf xs ys =
  List.exists (fun x -> List.exists (fun y -> conf x y) ys) xs;;

let remove_conflictsBy conf xss = filter (fun xs -> not (conf xs)) xss;;


(* ************************* *)
(* Substitutions             *)
(* ************************* *)

let dom_sub sub =
  match sub with
    | Subst(x,_)    -> x
    | NegSubst(x,_) -> x
;;

let eq_subBy eqx eqv sub sub' =
  match (sub,sub') with 
    | (Subst(x,v),Subst(x',v'))       -> (eqx x x') && (eqv v v')
    | (NegSubst(x,v),NegSubst(x',v')) -> (eqx x x') && (eqv v v')
    | _                               -> false
;;

(* NOTE: functor *)
let eq_sub sub sub' = eq_subBy SUB.eq_mvar SUB.eq_val sub sub'

let eq_subst th th' = setequalBy eq_sub th th';;

let merge_subBy eqx (===) (>+<) sub sub' =
  match (sub,sub',eqx (dom_sub sub) (dom_sub sub')) with
    | (Subst (x,v),Subst (x',v'),true) -> 
	if (v === v')
	then Some [Subst(x, v >+< v')]
	else None
    | (NegSubst(x,v),Subst(x',v'),true) ->
	if (not (v === v'))
	then Some [Subst(x',v')]
	else None
    | (Subst(x,v),NegSubst(x',v'),true) ->
	if (not (v === v'))
	then Some [Subst(x,v)]
	else None
    | _ -> Some [sub;sub']
;;

(* NOTE: functor *)
let merge_sub sub sub' = 
  merge_subBy SUB.eq_mvar SUB.eq_val SUB.merge_val sub sub'

(*
let rec fold_subst theta =
  let rec foo acc_th sub =
    match acc_th with
      | [] -> []
      | (s::ss) -> 
	  match (merge_sub s sub) with
	    | None -> raise NEVER_CTL
	    | Some subs -> subs @ (foo ss sub)
  in
    foldl foo [] theta
;;
*)

let clean_substBy eq cmp theta = List.sort cmp (nubBy eq theta);;

(* NOTE: we sort by using the generic "compare" on (meta-)variable
 *   names; we could also require a definition of compare for meta-variables 
 *   or substitutions but that seems like overkill for sorting
 *)
let clean_subst theta = 
  clean_substBy eq_sub (fun s s' -> compare (dom_sub s) (dom_sub s')) theta;;

let top_subst = [];;			(* Always TRUE subst. *)


(* Split a theta in two parts: one with (only) "x" and one without *)
(* NOTE: functor *)
let split_subst theta x = 
  partition (fun sub -> SUB.eq_mvar (dom_sub sub) x) theta;;

(* We only want to know if there is a conflict so we don't care
 * about merging of values
 *)
let conflict_subBy eqx (===) sub sub' = 
  (merge_subBy eqx (===) (fun x _ -> x) sub sub') = None;;

(* NOTE: functor *)
let conflict_sub sub sub' = 
  conflict_subBy SUB.eq_mvar SUB.eq_val sub sub';;

let conflict_subst theta theta' = conflictBy conflict_sub theta theta';;

(* Returns an option since conjunction may fail (incompatible subs.) *)
(* FIX ME: do proper cleanup *)
let conj_subst theta theta' =
  if (conflict_subst theta theta') 
  then None 
  else Some (clean_subst (unionBy eq_sub theta theta'))
;;

let negate_sub sub =
  match sub with
    | Subst(x,v)    -> NegSubst (x,v)
    | NegSubst(x,v) -> Subst(x,v)
;;

(* Turn a (big) theta into a list of (small) thetas *)
let negate_subst theta = (map (fun sub -> [negate_sub sub]) theta);;


(* ************************* *)
(* Witnesses                 *)
(* ************************* *)

let top_wit = [];;			(* Always TRUE witness *)

let eq_wit wit wit' = wit = wit';;

let union_wit wit wit' = union wit wit';;

let negate_wit wit =
  match wit with
    | Wit(s,th,anno,ws)    -> NegWit(s,th,anno,ws)
    | NegWit(s,th,anno,ws) -> Wit(s,th,anno,ws)
;;

let negate_wits wits = setify (map (fun wit -> [negate_wit wit]) wits);;


(* ************************* *)
(* Triples                   *)
(* ************************* *)

(* Triples are equal when the constituents are equal *)
let eq_trip (s,th,wit) (s',th',wit') =
  (s = s') && (eq_subst th th') && (eq_wit wit wit');;

let triples_cleanBy eq cmp trips = List.sort cmp (nubBy eq trips);;

let triples_clean trips = triples_cleanBy eq_trip compare trips;;

let triples_top states = map (fun s -> (s,top_subst,top_wit)) states;;

let triples_union trips trips' = unionBy eq_trip trips trips';;

let triples_conj trips trips' =
  setify (
    List.fold_left
      (function rest ->
	 function (s1,th1,wit1) ->
	   List.fold_left
	     (function rest ->
		function (s2,th2,wit2) ->
		  if (s1 = s2) then
		    match (conj_subst th1 th2) with
		      | Some th -> (s1,th,union_wit wit1 wit2)::rest
		      | _       -> rest
		  else rest)
	     rest trips')
      [] trips)
;;

let triple_negate states (s,th,wits) = 
  let negstates = map (fun st -> (st,top_subst,top_wit)) (setdiff states [s]) in
  let negths = map (fun th -> (s,th,top_wit)) (negate_subst th) in
  let negwits = map (fun nwit -> (s,th,nwit)) (negate_wits wits) in
    triples_union negstates (triples_union negths negwits)
;;

(* FIX ME: optimise; it is not necessary to do full conjunction *)
let rec triples_complement states trips =
  let rec loop states trips =
  match trips with
    | [] -> []
    | (t::[]) -> triple_negate states t
    | (t::ts) -> 
	triples_conj (triple_negate states t) (loop states ts) in
  setify (loop states trips)
;;


let triples_witness x trips = 
  let mkwit (s,th,wit) =
    let (th_x,newth) = split_subst th x in
      (s,newth,[Wit(s,th_x,[],wit)]) in	(* [] = annotation *)
    setify (map mkwit trips)
;;



(* ---------------------------------------------------------------------- *)
(* SAT  - Model Checking Algorithm for CTL-FVex                           *)
(*                                                                        *)
(* TODO: Implement _all_ operators (directly)                             *)
(* ---------------------------------------------------------------------- *)


(* ************************************* *)
(* The SAT algorithm and special helpers *)
(* ************************************* *)

let pre_concatmap f l =
  List.fold_left (function rest -> function cur -> union (f cur) rest) [] l

let rec pre_exist (grp,_,_) y =
  let exp (s,th,wit) = map (fun s' -> (s',th,wit)) (G.predecessors grp s) in
  setify (pre_concatmap exp y)
;;

let pre_forall ((_,_,states) as m) y = 
  triples_complement states (pre_exist m (triples_complement states y));;

let satAF m s =
  let f y = union y (pre_forall m y) in
  setfix f s
;;

let satEX m s = pre_exist m s;;

(* A[phi1 U phi2] == phi2 \/ (phi1 /\ AXA[phi1 U phi2]) *)
let satAU m s1 s2 = 
  let f y = triples_union s2 (triples_conj s1 (pre_forall m y)) in 
    setfix f []
;;

(* E[phi1 U phi2] == phi2 \/ (phi1 /\ EXE[phi1 U phi2]) *)
let satEU m s1 s2 = 
  let f y = triples_union s2 (triples_conj s1 (pre_exist m y)) in 
    setfix f []
;;




let rec satloop ((grp,label,states) as m) phi env =
  match unwrap phi with
    False              -> []
  | True               -> triples_top states
  | Pred(p)            -> label(p)		(* NOTE: Assume well-formed *)
  | Not(phi)           -> triples_complement states (satloop m phi env)
  | Or(phi1,phi2)      -> triples_union
	                    (satloop m phi1 env) (satloop m phi2 env)
  | And(phi1,phi2)     -> triples_conj
	                    (satloop m phi1 env) (satloop m phi2 env)
  | EX(phi)            -> satEX m (satloop m phi env)
  | AX(phi1)            ->
      satloop m
	(rewrap phi (Not (rewrap phi (EX (rewrap phi (Not phi1)))))) env
  | EF(phi)            -> satloop m (rewrap phi (EU(rewrap phi True,phi))) env
  | AF(phi)            -> satAF m (satloop m phi env)
  | EG(phi1)            ->
      satloop m
	(rewrap phi (Not(rewrap phi (AF (rewrap phi (Not phi1)))))) env
  | AG(phi1)            ->
      satloop m
	(rewrap phi (Not(rewrap phi (EF(rewrap phi (Not phi1)))))) env
  | EU(phi1,phi2)      -> satEU m (satloop m phi1 env) (satloop m phi2 env)
  | AU(phi1,phi2)      -> 
      satAU m (satloop m phi1 env) (satloop m phi2 env)
      (* old: satAF m (satloop m phi2 env) *)
  | Implies(phi1,phi2) ->
      satloop m (rewrap phi (Or(rewrap phi (Not phi1),phi2))) env
  | Exists (v,phi)     -> triples_witness v (satloop m phi env)
  | Let(v,phi1,phi2)   -> satloop m phi2 ((v,(satloop m phi1 env)) :: env)
  | Ref(v)             -> List.assoc v env
;;

let sat m phi = satloop m phi []
;;

(* SAT with tracking *)
let rec sat_verbose_loop annot maxlvl lvl ((_,label,states) as m) phi env =
  let anno res children = (annot lvl phi res children,res) in
  let satv phi0 env = sat_verbose_loop annot maxlvl (lvl+1) m phi0 env in
    if (lvl > maxlvl) && (maxlvl > -1) then
      anno (satloop m phi env) []
    else
      match unwrap phi with
	  False              -> anno [] []
	| True               -> anno (triples_top states) []
	| Pred(p)            -> anno (label(p)) []
	| Not(phi1)          -> 
	    let (child,res) = satv phi1 env in
	      anno (triples_complement states res) [child]
	| Or(phi1,phi2)      -> 
	    let (child1,res1) = satv phi1 env in
	    let (child2,res2) = satv phi2 env in
	      anno (triples_union res1 res2) [child1; child2]
	| And(phi1,phi2)     -> 
	    let (child1,res1) = satv phi1 env in
	    let (child2,res2) = satv phi2 env in
	      anno (triples_conj res1 res2) [child1; child2]
	| EX(phi1)           -> 
	    let (child,res) = satv phi1 env in
	      anno (satEX m res) [child]
	| AX(phi1)           -> 
	    let (child,res) = satv phi1 env in
	      anno (pre_forall m res) [child]
	| EF(phi1)           -> 
	    let (child,_) = satv phi1 env in
	      anno (satloop m (rewrap phi (EU(rewrap phi True,phi1))) env)
	      [child]
	| AF(phi1)           -> 
	    let (child,res) = satv phi1 env in
	      anno (satAF m res) [child]
	| EG(phi1)           -> 
	    let (child,_) = satv phi1 env in
	    anno
	      (satloop m
		 (rewrap phi (Not(rewrap phi (AF(rewrap phi (Not phi1))))))
		 env)
	      [child]
	| AG(phi1)            -> 
	    let (child,_) = satv phi1 env in
	    anno
	      (satloop m
		 (rewrap phi (Not(rewrap phi (EF(rewrap phi (Not phi1))))))
		 env)
	      [child]
	| EU(phi1,phi2)      -> 
	    let (child1,res1) = satv phi1 env in
	    let (child2,res2) = satv phi2 env in
	      anno (satEU m res1 res2) [child1; child2]
	| AU(phi1,phi2)      -> 
	    let (child1,res1) = satv phi1 env in
	    let (child2,res2) = satv phi2 env in
	      anno (satAU m res1 res2) [child1; child2]
	| Implies(phi1,phi2) -> 
	    let (child1,_) = satv phi1 env in
	    let (child2,_) = satv phi2 env in
	    anno
	      (satloop m (rewrap phi (Or(rewrap phi (Not phi1),phi2))) env)
	      [child1; child2]
	| Exists (v,phi1)    -> 
	    let (child,res) = satv phi1 env in
	      anno (triples_witness v res) [child]
	| Let(v,phi1,phi2)   ->
	    let (child1,res1) = satv phi1 env in
	    let (child2,res2) = satv phi2 ((v,res1) :: env) in
	    anno res2 [child1;child2]
	| Ref(v)             -> anno (List.assoc v env) []
;;

let sat_verbose annotate maxlvl lvl m phi =
  sat_verbose_loop annotate maxlvl lvl m phi []

(* Type for annotations collected in a tree *)
type ('a) witAnnoTree = WitAnno of ('a * ('a witAnnoTree) list);;

let sat_annotree annotate m phi =
  let tree_anno l phi res chld = WitAnno(annotate l phi res,chld) in
    sat_verbose_loop tree_anno (-1) 0 m phi []
;;


(* ********************************************************************** *)
(* End of Module: CTL_ENGINE                                              *)
(* ********************************************************************** *)
end
;;

