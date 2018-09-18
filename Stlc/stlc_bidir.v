(** * Bidirectional type checking for STLC. *)

(* GALLINETTE seminar, Semptember 17-18, 2018 *)

Require Import String.
Require Import stlc.
Require Import Utf8.
Set Implicit Arguments.

(** The syntax for STLC with type casts *)

(* Alternatively, we could have annotated lambda abstractions like this:
   [ALamAnn : string -> Ty -> CExp -> CExp], i.e. [λ (x : A). t].
   Then infer is always defined.
   Use as a core language.
   And we start with partially annotated terms (or not annotated at all) and try to recover fully annotated terms.
   We can fo this using the following functions:
   infer_decorate : part. annotated -> annotated (= option (Exp × Ty))
   check_decorate : part. annotated -> annotated
   (mutially recursive; can fail, if there is not enough information)

   We could convert from one representation to another, but Annotated Lambdas -> Casts requires type inference.
 *)
Inductive CExp : Set :=
  | AInt : nat -> CExp
  | AVar : string -> CExp
  | ALam : string -> CExp -> CExp
  | AApp : CExp -> CExp -> CExp
  | ACast : CExp -> Ty -> CExp.

Reserved Notation "[ Gamma |- a ::: A ] ".

(** The typing rules for the STLC with annotations *)
Inductive TypingAnn : TEnv -> CExp -> Ty -> Prop :=
  | atyInt : forall (Gamma : TEnv) (n : nat),
      [ Gamma |- (AInt n) ::: tInt ]
  | atyVar : forall (Gamma : TEnv) (x : string) (A : Ty),
      lookEnv Gamma x = Some(A) ->
      [ Gamma |- (AVar x) ::: A ]
  | atyLam : forall (Gamma : TEnv) (x : string) (b : CExp) (A B : Ty),
      [ Gamma, x @ A |- b ::: B ] ->
      [ Gamma |- (ALam x b) ::: (A :-> B)]
  | atyApp : forall (Gamma : TEnv) (f a : CExp) (A B : Ty),
      [ Gamma |- f ::: (A :-> B) ]->
      [ Gamma |- a ::: A ] ->
      [ Gamma |- (AApp f a) ::: B ]
  | atyCast : forall (Gamma : TEnv) (e : CExp) (A : Ty),
      [ Gamma |- e ::: A ] -> [ Gamma |- ACast e A ::: A]
where "[ Gamma |- a ::: A ]" := (TypingAnn Gamma a A).

Fixpoint ty_eqb (ty1 ty2 : Ty) : bool :=
  match ty1,ty2 with
  | tInt, tInt => true
  | tArr ty1 ty2, tArr ty1' ty2' => andb (ty_eqb ty1 ty1') (ty_eqb ty2 ty2')
  | _,_ => false
  end.

Fixpoint infer (G : TEnv) (e : CExp) : option Ty :=
  match e with
  | AInt n => Some tInt
  | AVar v => lookEnv G v
  | ALam x t1 => None (* with the "annotated lambdas" syntax it would be [ALamAnn x ty t => (infer (G,ty) t)] *)
  | AApp t1 t2 => match infer G t1 with
                  | Some (tArr ty1 ty2) => if (check G t2 ty1) then Some ty2 else None
                  | Some _ => None
                  | _ => None
                  end
  | ACast t ty => if check G t ty then Some ty else None
  end
  with check (G : TEnv) (e : CExp) (ty : Ty) : bool :=
         match e with
         | AInt n => ty_eqb ty tInt
         | AVar v as t => (*  should be: [infer G t] and compare the result of the call, but we have to inline the case from [infer] due to the issues with fixpoint *)
                         match (lookEnv G v) with
                          | Some ty' => ty_eqb ty' ty
                          | None => false
                          end
         | ALam x t1 as t => match ty with
                                 | tArr ty1' ty2' => check (cons G x ty1') t1 ty2'
                                 | tInt => false
                             end
         | AApp t1 t2 as t =>
           match (
             (*  should be: [infer G t], but again, this breaks a fixpoint, so we just inline *)
               match infer G t1 with
                  | Some (tArr ty1 ty2) => if (check G t2 ty1) then Some ty2 else None
                  | Some _ => None
                  | _ => None
                  end
             ) with
             Some ty' => ty_eqb ty ty'
           | None => false
           end
         | ACast t ty' => andb (ty_eqb ty ty') (check G t ty')
         end.

Local Coercion AInt : nat >-> CExp.

Definition v := AVar.

Notation "'λλ' x ',' t" := (ALam x t) (at level 100).
Notation "'(' t ':::' A ')'" := (ACast t A).
Notation "t @ u" := (AApp t u) (at level 100).

Eval compute in check empty 0 tInt.

Eval compute in infer empty
                      ((λλ "x", v"x") :::  (tInt :-> tInt)).

Eval compute in check empty
                      (((λλ "x", v"x") :::  (tInt :-> tInt)) @ 0) tInt.


Axiom ty_eqb_true : ∀ A B, ty_eqb A B = true -> A = B.
Axiom infer_sound : ∀ Γ t A, infer Γ t = Some A -> [ Γ |- t ::: A].

Theorem check_sound : ∀ Γ t A, (check Γ t A = true -> [ Γ |- t ::: A])
                            /\ ( infer Γ t = Some A -> [ Γ |- t ::: A]).
Proof.
  intros Γ t. revert Γ. induction t; intros Γ A;split;intros H0;inversion H0 as [H].
  - rewrite (ty_eqb_true _ _ H).
    now apply atyInt.
  - now apply atyInt.
  - apply atyVar.
    destruct (lookEnv Γ s);[|inversion H].
    now rewrite (ty_eqb_true _ _ H).
  - now apply atyVar.    
  - destruct A;[inversion H|].
    apply atyLam.
    now apply (proj1 (IHt _ _ )).
  - remember (infer Γ t1) as bli.
    destruct bli;[|discriminate H].
    destruct t;[discriminate H|].
    remember (check Γ t2 t3) as bla.
    destruct bla;[|discriminate H];symmetry in Heqbli,Heqbla.
    apply (proj2 (IHt1 _ _ )) in Heqbli.
    apply IHt2 in Heqbla.
    apply ty_eqb_true in H;subst.
    now apply atyApp with t3. 
  - remember (infer Γ t1) as bli.
    destruct bli;[|discriminate H].
    destruct t;[discriminate H|].
    remember (check Γ t2 t3) as bla.
    destruct bla;[|discriminate H];symmetry in Heqbli,Heqbla.
    apply (proj2 (IHt1 _ _ )) in Heqbli.
    apply IHt2 in Heqbla.
    inversion H;subst.
    now apply atyApp with t3.
  - apply Bool.Is_true_eq_left,Bool.andb_prop_elim in H as [H1 H2].
    apply Bool.Is_true_eq_true,ty_eqb_true in H1.
    apply Bool.Is_true_eq_true in H2;subst.
    apply atyCast.
    now apply (proj1 (IHt _ _)).
  - remember (check Γ t t0) as che.
    destruct che;[|discriminate H].
    inversion H; subst.
    symmetry in Heqche.
    apply atyCast.
    now apply (proj1 (IHt _ _)).
Qed.