(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


let js_obj_type_id () = 
  if Js_config.get_env () = Browser then
    Ast_literal.Lid.pervasives_js_obj
  else Ast_literal.Lid.js_obj 
    
let curry_type_id () = 
  if Js_config.get_env () = Browser then 
    Ast_literal.Lid.pervasives_uncurry
  else 
    Ast_literal.Lid.js_fn 

let meth_type_id () = 
  if Js_config.get_env () = Browser then 
    Ast_literal.Lid.pervasives_meth
  else 
    Ast_literal.Lid.js_meth

open Ast_helper 
let arrow = Ast_helper.Typ.arrow
let lift_js_type ~loc  x  = Typ.constr ~loc {txt = js_obj_type_id (); loc} [x]
let lift_curry_type ~loc x  = Typ.constr ~loc {txt = curry_type_id (); loc} [x]

let lift_js_meth ~loc (obj,meth) 
  = Typ.constr ~loc {txt = meth_type_id () ; loc} [obj; meth]

let down_with_name ~loc obj name =
  let downgrade ~loc () = 
    let var = Typ.var ~loc "a" in 
    Ast_comb.arrow_no_label ~loc
      (lift_js_type ~loc var) var
  in
  Ast_comb.local_extern_cont loc  
    ~pval_prim:["js_unsafe_downgrade"] 
    ~pval_type:(downgrade ~loc ())
    ~local_fun_name:"cast" 
    (fun down -> Exp.send ~loc (Exp.apply ~loc down ["", obj]) name  )
       
let destruct_tuple_exp (exp : Parsetree.expression) : Parsetree.expression list = 
  match exp with 
  | {pexp_desc = 
       Pexp_tuple [arg ; {pexp_desc = Pexp_ident{txt = Lident "__"; _}} ]
    ; _} -> 
    [arg]
  | {pexp_desc = Pexp_tuple args; _} -> args
  | {pexp_desc = Pexp_construct ({txt = Lident "()"}, None); _} -> []
  | v -> [v]
let destruct_tuple_pat (pat : Parsetree.pattern) : Parsetree.pattern list = 
  match pat with 
  | {ppat_desc = Ppat_tuple [arg ; {ppat_desc = Ppat_var{txt = "__"}} ]; _} -> 
    [arg]
  | {ppat_desc = Ppat_tuple args; _} -> args
  | {ppat_desc = Ppat_construct ({txt = Lident "()"}, None); _} -> []
  | v -> [v]

let destruct_tuple_typ (args : Parsetree.core_type)  = 
  match args with
  | {ptyp_desc = 
       Ptyp_tuple 
         [arg ; {ptyp_desc = Ptyp_constr ({txt = Lident "__"}, [])} ]; 
     _} 
    -> [ arg]
  | {ptyp_desc = Ptyp_tuple args; _} -> args 

  | {ptyp_desc = Ptyp_constr ({txt = Lident "unit"}, []); _} -> []
  | v -> [v]


let gen_fn_run loc arity fn args  : Parsetree.expression_desc = 
  let pval_prim = ["js_fn_run" ; string_of_int arity]  in
  let fn_type, tuple_type = Ast_comb.tuple_type_pair ~loc `Run arity  in 
  let pval_type =
    arrow ~loc "" (lift_curry_type ~loc tuple_type) fn_type in 
  Ast_comb.create_local_external loc ~pval_prim ~pval_type 
    (("", fn) :: List.map (fun x -> "",x) args )

(** The first argument is object itself which is only 
    for typing checking*)
let gen_method_run loc arity fn args : Parsetree.expression_desc = 
  let pval_prim = ["js_fn_runmethod" ; string_of_int arity]  in
  let fn_type, (obj_type, tuple_type) = Ast_comb.obj_type_pair ~loc  arity  in 
  let pval_type =
    arrow ~loc "" (lift_js_meth ~loc (obj_type, tuple_type)) fn_type in 
  Ast_comb.create_local_external loc ~pval_prim ~pval_type 
    (("", fn) :: List.map (fun x -> "",x) args )


let gen_fn_mk loc arity arg  : Parsetree.expression_desc = 
  let pval_prim = [ "js_fn_mk"; string_of_int arity]  in
  let fn_type , tuple_type = Ast_comb.tuple_type_pair ~loc `Make arity  in 
  let pval_type = arrow ~loc "" fn_type (lift_curry_type ~loc tuple_type)in
  Ast_comb.create_local_external loc ~pval_prim ~pval_type [("", arg)]

let gen_method_mk loc arity arg  : Parsetree.expression_desc = 
  let pval_prim = [ "js_fn_method"; string_of_int arity]  in
  let fn_type , (obj_type, tuple_type) = Ast_comb.obj_type_pair ~loc  arity  in 
  let pval_type = 
    arrow ~loc "" fn_type (lift_js_meth ~loc (obj_type, tuple_type))
  in
  Ast_comb.create_local_external loc ~pval_prim ~pval_type [("", arg)]

let uncurry_fn_gen loc 
    (pat : Parsetree.pattern) (body : Parsetree.expression)
  =
  let args = destruct_tuple_pat pat in 
  let len = List.length args in 
  let fun_ = 
    if len = 0 then 
      Ast_comb.fun_no_label ~loc (Ast_literal.pat_unit ~loc () ) body
    else 
      List.fold_right (Ast_comb.fun_no_label ~loc ) args body in
  gen_fn_mk loc len fun_

let uncurry_method_gen  loc 
    (pat : Parsetree.pattern)
    (body : Parsetree.expression) 
  = 
  let args = destruct_tuple_pat pat in 
  let len = List.length args - 1 in 
  let fun_ = 
    if len < 0 then 
      Location.raise_errorf ~loc "method expect at least one argument"
    else 
      List.fold_right (Ast_comb.fun_no_label ~loc) args body in
   gen_method_mk loc len fun_



        

let find_uncurry_attrs_and_remove (attrs : Parsetree.attributes ) = 
  Ext_list.exclude_with_fact (function 
    | ({Location.txt  = "uncurry"}, _) -> true 
    | _ -> false ) attrs 


(** 
   Turn {[ int -> int -> int ]} 
   into {[ (int *  int * int) fn ]}
*)
let uncurry_fn_type loc ty attrs
    (args : Parsetree.core_type ) body  : Parsetree.core_type = 
  let tyvars = destruct_tuple_typ args in 
  let arity = List.length tyvars in 
  if arity = 0 then lift_curry_type ~loc body 
  else lift_curry_type ~loc (Typ.tuple ~loc ~attrs (tyvars @ [body]))


let from_labels ~loc (labels : Asttypes.label list) : Parsetree.core_type = 
  let arity = List.length labels in 
  let tyvars = (Ext_list.init arity (fun i ->      
      Typ.var ~loc ("a" ^ string_of_int i))) in 

  let result_type =
    lift_js_type ~loc  
    @@ Typ.object_ ~loc (List.map2 (fun x y -> x ,[], y) labels tyvars) Closed

  in 
  List.fold_right2 
    (fun label tyvar acc -> arrow ~loc label tyvar acc) labels tyvars  result_type

let handle_debugger loc payload = 
  if Ast_payload.as_empty_structure payload then
    let predef_unit_type = Ast_literal.type_unit ~loc () in
    let pval_prim = ["js_debugger"] in
    Ast_comb.create_local_external loc 
      ~pval_prim
      ~pval_type:(arrow "" predef_unit_type predef_unit_type)
      [("",  Ast_literal.val_unit ~loc ())]
  else Location.raise_errorf ~loc "bs.raw can only be applied to a string"


let handle_raw loc payload = 
  begin match Ast_payload.as_string_exp payload with 
    | None -> 
      Location.raise_errorf ~loc "bs.raw can only be applied to a string"
    | Some exp -> 
      let pval_prim = ["js_pure_expr"] in
      { exp with pexp_desc = Ast_comb.create_local_external loc 
                     ~pval_prim
                     ~pval_type:(arrow "" 
                                   (Ast_literal.type_string ~loc ()) 
                                   (Ast_literal.type_any ~loc ()) )

                     ["",exp]}
  end

let handle_raw_structure loc payload = 
  begin match Ast_payload.as_string_exp payload with 
    | Some exp 
      -> 
      let pval_prim = ["js_pure_stmt"] in 
      Ast_helper.Str.eval 
        { exp with pexp_desc =
                     Ast_comb.create_local_external loc 
                       ~pval_prim
                       ~pval_type:(arrow ""
                                     (Ast_literal.type_string ~loc ())
                                     (Ast_literal.type_any ~loc ()))
                       ["",exp]}
    | None
      -> 
      Location.raise_errorf ~loc "bs.raw can only be applied to a string"
  end