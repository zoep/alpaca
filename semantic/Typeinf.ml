open Error
open Types
open Identifier
open Symbol
open Printf
open Symbtest
open Format

let fresh =
  let k = ref 0 in
    fun () -> incr k; T_Alpha !k

let freshDim =
  let k = ref 0 in
    fun () -> incr k; D_Alpha !k

let refresh ty = 
  match ty with
    | T_Notype -> fresh ()
    | _        -> ty

let rec notIn alpha typ = match typ with
  | T_Alpha n -> alpha != (T_Alpha n)
  | T_Arrow (t1, t2) -> (notIn alpha t1) && (notIn alpha t2)
  | T_Array(a,n) -> a != alpha 
  | T_Ref tref -> tref != alpha
  | T_Int  | T_Char  | T_Str | T_Unit| T_Id _ 
  | T_Ord | T_Bool | T_Float | T_Notype -> true

let rec singleSub alpha t2 typ = match alpha, typ with
  | T_Alpha a, T_Alpha n when a = n -> t2
  | T_Alpha _, T_Alpha _ -> typ
  | T_Alpha _, T_Arrow (typ1,typ2) -> T_Arrow ((singleSub alpha t2 typ1),(singleSub alpha t2 typ2))
  | T_Alpha _, T_Ref typ1 -> T_Ref (singleSub alpha t2 typ1)
  | T_Alpha _, T_Array (typ1,n)-> T_Array ((singleSub alpha t2 typ1),n)
  | T_Alpha _, _ -> typ
  | _, _ -> failwith "must be alpha"

let subc alpha tau c =
  let walk (tau1, tau2) = (singleSub alpha tau tau1, singleSub alpha tau tau2) in
    List.map walk c
  
let rec singleSubDim alpha d dim1 = match alpha, dim1 with 
  | D_Alpha a, D_Alpha b when a = b -> d
  | D_Alpha _, D_Alpha b -> D_Alpha b
  | D_Alpha _, _ -> dim1
  | _, _ -> failwith "Must be D_Alpha"

let subDim alpha d lst =
  let walk (dim1, dim2) = (singleSubDim alpha d dim1, singleSubDim alpha d dim2) in
    List.map walk lst

let rec singleSubArray alpha d tau = match alpha, tau with
  | alpha, T_Array (tau, dim1) -> T_Array (tau, singleSubDim alpha d dim1)
  | _, tau -> tau

let subArray alpha d lst =
  let walk (dim1, dim2) = (singleSubArray alpha d dim1, singleSubArray alpha d dim2) in
    List.map walk lst

let equalsType tau1 tau2  = match tau1, tau2 with
  | T_Ord, tau | tau, T_Ord -> (tau = T_Int) || (tau = T_Float) || (tau = T_Char)
  | tau1, tau2 -> tau1 = tau2

let unify c =
  let rec unifyDims dims acc = match dims with
    | [] -> acc
    | (D_Int a, D_Int b) :: lst when a = b -> unifyDims lst acc 
    | (D_Alpha alpha, dim2) :: lst -> unifyDims (subDim (D_Alpha alpha) dim2 lst) (subArray (D_Alpha alpha) dim2 acc)  
    | (dim1, D_Alpha alpha) :: lst -> unifyDims (subDim (D_Alpha alpha) dim1 lst) (subArray (D_Alpha alpha) dim1 acc)
    | (dim1, dim2) :: lst -> printf "Could not match dim %a with dim %a \n" pretty_dim dim1 pretty_dim dim2; raise Exit
  in 
  let rec unifyOrd ord acc = match ord with
    | [] -> acc 
    | (tau1, tau2) :: c when (equalsType tau1 tau2) -> unifyOrd c acc
    | (T_Alpha alpha, T_Ord) :: c | (T_Ord, T_Alpha alpha) :: c -> 
        unifyOrd (subc (T_Alpha alpha) T_Ord c) ((T_Alpha alpha, T_Ord) :: (subc (T_Alpha alpha) T_Ord acc))
    | (typ1, typ2) :: lst -> printf "Could not match type %a with type %a \n" pretty_typ typ1 pretty_typ typ2; raise Exit  
  in
  let rec unifyAux c ord dims acc = match c with
    | [] -> 
      let acc' = unifyOrd ord acc in 
        unifyDims dims acc'
    | (tau1, tau2) :: c when equalsType tau1 tau2 -> 
      unifyAux c ord dims acc
    | (T_Ref tau1, T_Ref tau2) :: c -> 
      unifyAux ((tau1, tau2) :: c) ord dims acc
    | (T_Array (tau1, dim1), T_Array (tau2, dim2)) :: c -> 
      unifyAux ((tau1, tau2) :: c) ord ((dim1, dim2) :: dims) acc
    | (tau1, tau2) :: c when equalsType tau1 tau2 -> 
      unifyAux c ord dims acc
    | (T_Ord, tau2) :: c -> 
      unifyAux c ((T_Ord, tau2) :: ord) dims acc
    | (tau1, T_Ord) :: c -> 
      unifyAux c ((tau1, T_Ord) :: ord) dims acc
    | (T_Alpha alpha, tau2) :: c when notIn (T_Alpha alpha) tau2 ->
        unifyAux (subc (T_Alpha alpha) tau2 c) (subc (T_Alpha alpha) tau2 ord) dims ((T_Alpha alpha, tau2) :: (subc (T_Alpha alpha) tau2 acc))
    | (tau1, T_Alpha alpha) :: c when notIn (T_Alpha alpha) tau1 ->
        unifyAux (subc (T_Alpha alpha) tau1 c) (subc (T_Alpha alpha) tau1 ord) dims ((T_Alpha alpha, tau1) :: (subc (T_Alpha alpha) tau1 acc))
    | (T_Arrow (tau11, tau12), T_Arrow (tau21, tau22)) :: c ->
        unifyAux ((tau11, tau21) :: (tau12, tau22) :: c) ord dims acc
    | (typ1, typ2) :: lst -> printf "Could not match type %a with type %a \n" pretty_typ typ1  pretty_typ typ2; raise Exit
  in
    unifyAux c [] [] []


(* Old Unify
 
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
 *)

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
                                  begin
                                    match (try ( Some ( List.assoc param.parameter_type solved_types) ) with Not_found -> None) with
                                                | None -> ()
                                                | Some p_typ -> param.parameter_type <- p_typ 
                                  end
                               | _ -> failwith "Parameter must be a parameter\n"
                  ) f.function_paramlist
            | ENTRY_variable v -> 
                    begin  
                       match (try ( Some ( List.assoc v.variable_type solved_types) ) with Not_found -> None) with
                        | None -> ()
                        | Some v_typ ->  v.variable_type <- v_typ
                    end
            | _ -> failwith "Must be variable or function\n"
        end

let rec updateSymbolRec func_to_change solved_types = match func_to_change with
  | [] -> ()
  | (D_Var (fh, _))::t -> updateSymbol fh solved_types;
                          updateSymbolRec t solved_types
  | _ -> failwith "Must be D_Var\n"


