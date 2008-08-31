(* Copyright (c) 2008, Adam Chlipala
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice,
 *   this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * - The names of contributors may not be used to endorse or promote products
 *   derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *)

(* Pretty-printing core Ur/Web *)

structure CorePrint :> CORE_PRINT = struct

open Print.PD
open Print

open Core

structure E = CoreEnv

val debug = ref false

fun p_kind' par (k, _) =
    case k of
        KType => string "Type"
      | KArrow (k1, k2) => parenIf par (box [p_kind' true k1,
                                             space,
                                             string "->",
                                             space,
                                             p_kind k2])
      | KName => string "Name"
      | KRecord k => box [string "{", p_kind k, string "}"]
      | KUnit => string "Unit"
      | KTuple ks => box [string "(",
                          p_list_sep (box [space, string "*", space]) p_kind ks,
                          string ")"]

and p_kind k = p_kind' false k

fun p_con' par env (c, _) =
    case c of
        TFun (t1, t2) => parenIf par (box [p_con' true env t1,
                                           space,
                                           string "->",
                                           space,
                                           p_con env t2])
      | TCFun (x, k, c) => parenIf par (box [string x,
                                             space,
                                             string "::",
                                             space,
                                             p_kind k,
                                             space,
                                             string "->",
                                             space,
                                             p_con (E.pushCRel env x k) c])
      | TRecord (CRecord (_, xcs), _) => box [string "{",
                                              p_list (fn (x, c) =>
                                                         box [p_name env x,
                                                              space,
                                                              string ":",
                                                              space,
                                                              p_con env c]) xcs,
                                              string "}"]
      | TRecord c => box [string "$",
                          p_con' true env c]

      | CRel n =>
        ((if !debug then
              string (#1 (E.lookupCRel env n) ^ "_" ^ Int.toString n)
          else
              string (#1 (E.lookupCRel env n)))
         handle E.UnboundRel _ => string ("UNBOUND_" ^ Int.toString n))
      | CNamed n =>
        ((if !debug then
              string (#1 (E.lookupCNamed env n) ^ "__" ^ Int.toString n)
          else
              string (#1 (E.lookupCNamed env n)))
         handle E.UnboundNamed _ => string ("UNBOUNDN_" ^ Int.toString n))
      | CFfi (m, x) => box [string "FFI(", string m, string ".", string x, string ")"]

      | CApp (c1, c2) => parenIf par (box [p_con env c1,
                                           space,
                                           p_con' true env c2])
      | CAbs (x, k, c) => parenIf par (box [string "fn",
                                            space,
                                            string x,
                                            space,
                                            string "::",
                                            space,
                                            p_kind k,
                                            space,
                                            string "=>",
                                            space,
                                            p_con (E.pushCRel env x k) c])

      | CName s => box [string "#", string s]

      | CRecord (k, xcs) =>
        if !debug then
            parenIf par (box [string "[",
                              p_list (fn (x, c) =>
                                         box [p_con env x,
                                              space,
                                              string "=",
                                              space,
                                              p_con env c]) xcs,
                              string "]::",
                              p_kind k])
        else
            parenIf par (box [string "[",
                              p_list (fn (x, c) =>
                                         box [p_con env x,
                                              space,
                                              string "=",
                                              space,
                                              p_con env c]) xcs,
                              string "]"])
      | CConcat (c1, c2) => parenIf par (box [p_con' true env c1,
                                              space,
                                              string "++",
                                              space,
                                              p_con env c2])
      | CFold _ => string "fold"
      | CUnit => string "()"

      | CTuple cs => box [string "(",
                          p_list (p_con env) cs,
                          string ")"]
      | CProj (c, n) => box [p_con env c,
                             string ".",
                             string (Int.toString n)]
        
and p_con env = p_con' false env

and p_name env (all as (c, _)) =
    case c of
        CName s => string s
      | _ => p_con env all

fun p_enamed env n =
    (if !debug then
        string (#1 (E.lookupENamed env n) ^ "__" ^ Int.toString n)
     else
         string (#1 (E.lookupENamed env n)))
    handle E.UnboundNamed _ => string ("UNBOUNDN_" ^ Int.toString n)

fun p_con_named env n =
    (if !debug then
        string (#1 (E.lookupConstructor env n) ^ "__" ^ Int.toString n)
     else
         string (#1 (E.lookupConstructor env n)))
    handle E.UnboundNamed _ => string ("CONSTRUCTOR_" ^ Int.toString n)

fun p_patCon env pc =
    case pc of
        PConVar n => p_con_named env n
      | PConFfi {mod = m, con, ...} => box [string "FFIC(",
                                            string m,
                                            string ".",
                                            string con,
                                            string ")"]

fun p_pat' par env (p, _) =
    case p of
        PWild => string "_"
      | PVar (s, _) => string s
      | PPrim p => Prim.p_t p
      | PCon (_, n, _, NONE) => p_patCon env n
      | PCon (_, n, _, SOME p) => parenIf par (box [p_patCon env n,
                                                    space,
                                                    p_pat' true env p])
      | PRecord xps =>
        box [string "{",
             p_list_sep (box [string ",", space]) (fn (x, p, _) =>
                                                      box [string x,
                                                           space,
                                                           string "=",
                                                           space,
                                                           p_pat env p]) xps,
             string "}"]

and p_pat x = p_pat' false x

fun p_exp' par env (e, _) =
    case e of
        EPrim p => Prim.p_t p
      | ERel n =>
        ((if !debug then
              string (#1 (E.lookupERel env n) ^ "_" ^ Int.toString n)
          else
              string (#1 (E.lookupERel env n)))
         handle E.UnboundRel _ => string ("UNBOUND_" ^ Int.toString n))
      | ENamed n => p_enamed env n
      | ECon (_, pc, ts, NONE) => box [string "[",
                                       p_patCon env pc,
                                       p_list_sep (box []) (fn t => box [space, string "[", p_con env t, string "]"]) ts,
                                       string "]"]
      | ECon (_, pc, ts, SOME e) => box [string "[",
                                        p_patCon env pc,
                                        space,
                                        p_exp' true env e,
                                        p_list_sep (box []) (fn t => box [space, string "[", p_con env t, string "]"]) ts,
                                        string "]"]
      | EFfi (m, x) => box [string "FFI(", string m, string ".", string x, string ")"]
      | EFfiApp (m, x, es) => box [string "FFI(",
                                   string m,
                                   string ".",
                                   string x,
                                   string "(",
                                   p_list (p_exp env) es,
                                   string "))"]
      | EApp (e1, e2) => parenIf par (box [p_exp env e1,
                                           space,
                                           p_exp' true env e2])
      | EAbs (x, t, _, e) => parenIf par (box [string "fn",
                                               space,
                                               string x,
                                               space,
                                               string ":",
                                               space,
                                               p_con env t,
                                               space,
                                               string "=>",
                                               space,
                                               p_exp (E.pushERel env x t) e])
      | ECApp (e, c) => parenIf par (box [p_exp env e,
                                          space,
                                          string "[",
                                          p_con env c,
                                          string "]"])
      | ECAbs (x, k, e) => parenIf par (box [string "fn",
                                             space,
                                             string x,
                                             space,
                                             string "::",
                                             space,
                                             p_kind k,
                                             space,
                                             string "=>",
                                             space,
                                             p_exp (E.pushCRel env x k) e])

      | ERecord xes => box [string "{",
                            p_list (fn (x, e, _) =>
                                       box [p_name env x,
                                            space,
                                            string "=",
                                            space,
                                            p_exp env e]) xes,
                            string "}"]
      | EField (e, c, {field, rest}) =>
        if !debug then
            box [p_exp' true env e,
                 string ".",
                 p_con' true env c,
                 space,
                 string "[",
                 p_con env field,
                 space,
                 string " in ",
                 space,
                 p_con env rest,
                 string "]"]
        else
            box [p_exp' true env e,
                 string ".",
                 p_con' true env c]
      | ECut (e, c, {field, rest}) =>
        parenIf par (if !debug then
                         box [p_exp' true env e,
                              space,
                              string "--",
                              space,
                              p_con' true env c,
                              space,
                              string "[",
                              p_con env field,
                              space,
                              string " in ",
                              space,
                              p_con env rest,
                              string "]"]
                     else
                         box [p_exp' true env e,
                              space,
                              string "--",
                              space,
                              p_con' true env c])
      | EFold _ => string "fold"

      | ECase (e, pes, _) => parenIf par (box [string "case",
                                               space,
                                               p_exp env e,
                                               space,
                                               string "of",
                                               space,
                                               p_list_sep (box [space, string "|", space])
                                                          (fn (p, e) => box [p_pat env p,
                                                                             space,
                                                                             string "=>",
                                                                             space,
                                                                             p_exp (E.patBinds env p) e]) pes])

      | EWrite e => box [string "write(",
                         p_exp env e,
                         string ")"]

      | EClosure (n, es) => box [string "CLOSURE(",
                                 p_enamed env n,
                                 p_list_sep (string "") (fn e => box [string ", ",
                                                                      p_exp env e]) es,
                                 string ")"]

and p_exp env = p_exp' false env

fun p_vali env (x, n, t, e, s) =
    let
        val xp = if !debug then
                     box [string x,
                          string "__",
                          string (Int.toString n)]
                 else
                     string x        
    in
        box [xp,
             space,
             string "as",
             space,
             string s,
             space,
             string ":",
             space,
             p_con env t,
             space,
             string "=",
             space,
             p_exp env e]
    end

fun p_export_kind ck =
    case ck of
        Link => string "link"
      | Action => string "action"

fun p_datatype env (x, n, xs, cons) =
    let
        val k = (KType, ErrorMsg.dummySpan)
        val env = E.pushCNamed env x n (KType, ErrorMsg.dummySpan) NONE
        val env = foldl (fn (x, env) => E.pushCRel env x k) env xs

        val xp = if !debug then
                     string (x ^ "__" ^ Int.toString n)
                 else
                     string x
    in
        box [string "datatype",
             space,
             xp,
             p_list_sep (box []) (fn x => box [space, string x]) xs,
             space,
             string "=",
             space,
             p_list_sep (box [space, string "|", space])
                        (fn (x, n, NONE) => if !debug then (string (x ^ "__" ^ Int.toString n))
                                            else string x
                          | (x, n, SOME t) => box [if !debug then (string (x ^ "__" ^ Int.toString n))
                                                   else string x, space, string "of", space, p_con env t])
                        cons]
    end

fun p_decl env (dAll as (d, _) : decl) =
    case d of
        DCon (x, n, k, c) =>
        let
            val xp = if !debug then
                         box [string x,
                              string "__",
                              string (Int.toString n)]
                     else
                         string x
        in
            box [string "con",
                 space,
                 xp,
                 space,
                 string "::",
                 space,
                 p_kind k,
                 space,
                 string "=",
                 space,
                 p_con env c]
        end
      | DDatatype x => p_datatype env x
      | DVal vi => box [string "val",
                        space,
                        p_vali env vi]
      | DValRec vis =>
        let
            val env = E.declBinds env dAll
        in
            box [string "val",
                 space,
                 string "rec",
                 space,
                 p_list_sep (box [newline, string "and", space]) (p_vali env) vis]
        end
      | DExport (ek, n) => box [string "export",
                                space,
                                p_export_kind ek,
                                space,
                                p_enamed env n,
                                space,
                                string "as",
                                space,
                                p_con env (#2 (E.lookupENamed env n))]

fun p_file env file =
    let
        val (pds, _) = ListUtil.foldlMap (fn (d, env) =>
                                             (p_decl env d,
                                              E.declBinds env d))
                             env file
    in
        p_list_sep newline (fn x => x) pds
    end

end
