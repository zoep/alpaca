open Error
open Types
open Identifier
open Symbol

let fresh =
  let k = ref 0 in
    fun () -> incr k; T_Alpha !k

let refresh ty = 
  match ty with
    | T_Notype -> fresh ()
    | _        -> ty

let rec notIn alpha typ = match typ with
  | T_Alpha n -> alpha != (T_Alpha n)
  | T_Arrow (t1, t2) -> (notIn alpha t1) && (notIn alpha t2)
  | T_Array(a,n) -> a != alpha 
  | T_Ref tref -> tref != alpha
  | T_Int  | T_Char  | T_Str | T_Unit| T_Id _ (* must be handled *)
  | T_Bool | T_Float | T_Notype -> true

let rec singleSub alpha t2 typ = match alpha, typ with
  | T_Alpha a, T_Alpha n when a = n -> t2
  | T_Alpha _, T_Alpha _ -> typ
  | T_Alpha _, T_Arrow (typ1,typ2) -> T_Arrow ((singleSub alpha t2 typ1),(singleSub alpha t2 typ2))
  | T_Alpha _, T_Ref typ1-> T_Ref (singleSub alpha t2 typ1)
  | T_Alpha _, T_Array (typ1,n)-> T_Array ((singleSub alpha t2 typ1),n)
  | T_Alpha _, _ -> typ
  | _, _ -> failwith "must be alpha"

let rec subc alpha tau c =
  let walk (tau1, tau2) = (singleSub alpha tau tau1, singleSub alpha tau tau2) in
    List.map walk c

let unify c =
  let rec unifyAux c acc = match c with
    | [] -> acc
    | (tau1, tau2) :: c when tau1 = tau2 -> unifyAux c acc
    | (T_Alpha alpha, tau2) :: c when notIn (T_Alpha alpha) tau2 ->
        unifyAux (subc (T_Alpha alpha) tau2 c) ((T_Alpha alpha, tau2)::(subc (T_Alpha alpha) tau2 acc))
    | (tau1, T_Alpha alpha) :: c when notIn (T_Alpha alpha) tau1 ->
        unifyAux (subc (T_Alpha alpha) tau1 c) ((T_Alpha alpha, tau1)::(subc (T_Alpha alpha) tau1 acc))
    | (T_Arrow (tau11, tau12), T_Arrow (tau21, tau22)) :: c ->
        unifyAux ((tau11, tau21) :: (tau12, tau22) :: c) acc
    | _ -> failwith "ERROR !!! BOO !!!"
  in
    unifyAux c []

let updateSymbol func_header solved_types = match func_header with
  | [] -> failwith "func_header cannot be empty\n";
  | (id, _)::_ -> 
      let p = lookupEntry (id_make id) LOOKUP_ALL_SCOPES true in
        begin
          match p.entry_info with 
            | ENTRY_function f -> 
                let f_typ = List.assoc f.function_result solved_types in
                  f.function_result <- f_typ;
                  List.iter (fun param_entry -> match param_entry.entry_info with
                               | ENTRY_parameter param -> 
                                   let p_typ = List.assoc param.parameter_type solved_types in
                                     param.parameter_type <- p_typ 
                               | _ -> failwith "Parameter must be a parameter\n"
                  ) f.function_paramlist
            | ENTRY_variable v ->
                let v_typ = List.assoc v.variable_type solved_types in
                  v.variable_type <- v_typ
            | _ -> failwith "Must be variable or function\n"
        end

let rec updateSymbolRec func_to_change solved_types = match func_to_change with
  | [] -> ()
  | (D_Var (fh, _))::t -> updateSymbol fh solved_types;
                          updateSymbolRec t solved_types
  | _ -> failwith "Must be D_Var\n"
