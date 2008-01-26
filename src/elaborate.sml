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

structure Elaborate :> ELABORATE = struct

structure L = Source
structure L' = Elab
structure E = ElabEnv
structure U = ElabUtil

open Print
open ElabPrint

fun elabKind (k, loc) =
    case k of
        L.KType => (L'.KType, loc)
      | L.KArrow (k1, k2) => (L'.KArrow (elabKind k1, elabKind k2), loc)
      | L.KName => (L'.KName, loc)
      | L.KRecord k => (L'.KRecord (elabKind k), loc)

fun elabExplicitness e =
    case e of
        L.Explicit => L'.Explicit
      | L.Implicit => L'.Implicit

fun occursKind r =
    U.Kind.exists (fn L'.KUnif (_, r') => r = r'
                    | _ => false)

datatype kunify_error =
         KOccursCheckFailed of L'.kind * L'.kind
       | KIncompatible of L'.kind * L'.kind

exception KUnify' of kunify_error

fun kunifyError err =
    case err of
        KOccursCheckFailed (k1, k2) =>
        eprefaces "Kind occurs check failed"
        [("Kind 1", p_kind k1),
         ("Kind 2", p_kind k2)]
      | KIncompatible (k1, k2) =>
        eprefaces "Incompatible kinds"
        [("Kind 1", p_kind k1),
         ("Kind 2", p_kind k2)]

fun unifyKinds' (k1All as (k1, _)) (k2All as (k2, _)) =
    let
        fun err f = raise KUnify' (f (k1All, k2All))
    in
        case (k1, k2) of
            (L'.KType, L'.KType) => ()
          | (L'.KArrow (d1, r1), L'.KArrow (d2, r2)) =>
            (unifyKinds' d1 d2;
             unifyKinds' r1 r2)
          | (L'.KName, L'.KName) => ()
          | (L'.KRecord k1, L'.KRecord k2) => unifyKinds' k1 k2

          | (L'.KError, _) => ()
          | (_, L'.KError) => ()

          | (L'.KUnif (_, ref (SOME k1All)), _) => unifyKinds' k1All k2All
          | (_, L'.KUnif (_, ref (SOME k2All))) => unifyKinds' k1All k2All

          | (L'.KUnif (_, r1), L'.KUnif (_, r2)) =>
            if r1 = r2 then
                ()
            else
                r1 := SOME k2All

          | (L'.KUnif (_, r), _) =>
            if occursKind r k2All then
                err KOccursCheckFailed
            else
                r := SOME k2All
          | (_, L'.KUnif (_, r)) =>
            if occursKind r k1All then
                err KOccursCheckFailed
            else
                r := SOME k1All

          | _ => err KIncompatible
    end

exception KUnify of L'.kind * L'.kind * kunify_error

fun unifyKinds k1 k2 =
    unifyKinds' k1 k2
    handle KUnify' err => raise KUnify (k1, k2, err)

datatype con_error =
         UnboundCon of ErrorMsg.span * string
       | WrongKind of L'.con * L'.kind * L'.kind * kunify_error

fun conError env err =
    case err of
        UnboundCon (loc, s) =>
        ErrorMsg.errorAt loc ("Unbound constructor variable " ^ s)
      | WrongKind (c, k1, k2, kerr) =>
        (ErrorMsg.errorAt (#2 c) "Wrong kind";
         eprefaces' [("Constructor", p_con env c),
                     ("Have kind", p_kind k1),
                     ("Need kind", p_kind k2)];
         kunifyError kerr)

fun checkKind env c k1 k2 =
    unifyKinds k1 k2
    handle KUnify (k1, k2, err) =>
           conError env (WrongKind (c, k1, k2, err))

val dummy = ErrorMsg.dummySpan

val ktype = (L'.KType, dummy)
val kname = (L'.KName, dummy)

val cerror = (L'.CError, dummy)
val kerror = (L'.KError, dummy)

local
    val count = ref 0
in

fun resetKunif () = count := 0

fun kunif () =
    let
        val n = !count
        val s = if n <= 26 then
                    str (chr (ord #"A" + n))
                else
                    "U" ^ Int.toString (n - 26)
    in
        count := n + 1;
        (L'.KUnif (s, ref NONE), dummy)
    end

end

fun elabCon env (c, loc) =
    case c of
        L.CAnnot (c, k) =>
        let
            val k' = elabKind k
            val (c', ck) = elabCon env c
        in
            checkKind env c' ck k';
            (c', k')
        end

      | L.TFun (t1, t2) =>
        let
            val (t1', k1) = elabCon env t1
            val (t2', k2) = elabCon env t2
        in
            checkKind env t1' k1 ktype;
            checkKind env t2' k2 ktype;
            ((L'.TFun (t1', t2'), loc), ktype)
        end
      | L.TCFun (e, x, k, t) =>
        let
            val e' = elabExplicitness e
            val k' = elabKind k
            val env' = E.pushCRel env x k'
            val (t', tk) = elabCon env' t
        in
            checkKind env t' tk ktype;
            ((L'.TCFun (e', x, k', t'), loc), ktype)
        end
      | L.TRecord c =>
        let
            val (c', ck) = elabCon env c
            val k = (L'.KRecord ktype, loc)
        in
            checkKind env c' ck k;
            ((L'.TRecord c', loc), ktype)
        end

      | L.CVar s =>
        (case E.lookupC env s of
             E.CNotBound =>
             (conError env (UnboundCon (loc, s));
              (cerror, kerror))
           | E.CRel (n, k) =>
             ((L'.CRel n, loc), k)
           | E.CNamed (n, k) =>
             ((L'.CNamed n, loc), k))
      | L.CApp (c1, c2) =>
        let
            val (c1', k1) = elabCon env c1
            val (c2', k2) = elabCon env c2
            val dom = kunif ()
            val ran = kunif ()
        in
            checkKind env c1' k1 (L'.KArrow (dom, ran), loc);
            checkKind env c2' k2 dom;
            ((L'.CApp (c1', c2'), loc), ran)
        end
      | L.CAbs (e, x, k, t) =>
        let
            val e' = elabExplicitness e
            val k' = elabKind k
            val env' = E.pushCRel env x k'
            val (t', tk) = elabCon env' t
        in
            ((L'.CAbs (e', x, k', t'), loc),
             (L'.KArrow (k', tk), loc))
        end

      | L.CName s =>
        ((L'.CName s, loc), kname)

      | L.CRecord xcs =>
        let
            val k = kunif ()

            val xcs' = map (fn (x, c) =>
                               let
                                   val (x', xk) = elabCon env x
                                   val (c', ck) = elabCon env c
                               in
                                   checkKind env x' xk kname;
                                   checkKind env c' ck k;
                                   (x', c')
                               end) xcs
        in
            ((L'.CRecord (k, xcs'), loc), (L'.KRecord k, loc))
        end
      | L.CConcat (c1, c2) =>
        let
            val (c1', k1) = elabCon env c1
            val (c2', k2) = elabCon env c2
            val ku = kunif ()
            val k = (L'.KRecord ku, loc)
        in
            checkKind env c1' k1 k;
            checkKind env c2' k2 k;
            ((L'.CConcat (c1', c2'), loc), k)
        end

fun kunifsRemain k =
    case k of
        L'.KUnif (_, ref NONE) => true
      | _ => false

val kunifsInKind = U.Kind.exists kunifsRemain
val kunifsInCon = U.Con.exists {kind = kunifsRemain,
                                con = fn _ => false}

datatype decl_error =
         KunifsRemainKind of ErrorMsg.span * L'.kind
       | KunifsRemainCon of ErrorMsg.span * L'.con

fun declError env err =
    case err of
        KunifsRemainKind (loc, k) =>
        (ErrorMsg.errorAt loc "Some kind unification variables are undetermined in kind";
         eprefaces' [("Kind", p_kind k)])
      | KunifsRemainCon (loc, c) =>
        (ErrorMsg.errorAt loc "Some kind unification variables are undetermined in constructor";
         eprefaces' [("Constructor", p_con env c)])

fun elabDecl env (d, loc) =
    (resetKunif ();
     case d of
         L.DCon (x, ko, c) =>
         let
             val k' = case ko of
                          NONE => kunif ()
                        | SOME k => elabKind k

             val (c', ck) = elabCon env c
             val (env', n) = E.pushCNamed env x k'
         in
             checkKind env c' ck k';

             if kunifsInKind k' then
                 declError env (KunifsRemainKind (loc, k'))
             else
                 ();

             if kunifsInCon c' then
                 declError env (KunifsRemainCon (loc, c'))
             else
                 ();

             (env',
              (L'.DCon (x, n, k', c'), loc))
         end)

fun elabFile env ds =
    ListUtil.mapfoldl (fn (d, env) => elabDecl env d) env ds

end
