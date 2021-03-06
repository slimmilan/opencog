;; Background PLN reasoning
;;
;; Very simplistic and hacky at the moment, loop of 2 rules
;;
;; 1. Preprocessing to turn r2l outputs into something that PLN can reason on
;;
;; 2. Limited induction reasoning
;;
;; The reasoner doesn't use the URE. Instead if merely applies the 2
;; rules one after the other in a loop.
;;
;; You may test it as following (wait for a couple seconds between
;; each command to be sure that the chatbot-psi and the pln-reasoner
;; have time to diggest them.
;;
;; guile -l main.scm
;;
;; ;; positive sentence, also helps sureal to generate answer
;; (mock-HEAD-chat "p-1" "Eddie" "small animals are cute")
;;
;; ;; positive sentences
;; (mock-HEAD-chat "p-2" "Ruiting" "birds are lovely")
;; (mock-HEAD-chat "p-3" "Ben" "dogs are awesome")
;; (mock-HEAD-chat "p-3" "Ben" "the multiverse is beautiful")
;;
;; ;; negative sentences
;; (mock-HEAD-chat "p-3" "Ben" "I hate to relax, it makes me nervous")
;;
;; ;; Statement about Ben
;; (mock-HEAD-chat "p-1" "Eddie" "Ben is crazy")
;;
;; ;; Question about happiness. Answer should be: crazy people are happy
;; (mock-HEAD-chat "p-1" "Eddie" "What do you know about happy?")

(use-modules (opencog))
(use-modules (opencog logger))
(use-modules (opencog query))
(use-modules (srfi srfi-1))

;; (cog-logger-set-level! "debug")

;; Load PLN rule implication direct evaluation
(load-from-path "opencog/pln/rules/implication-direct-evaluation-rule.scm")

;;;;;;;;;;;;;;;
;; HEAD mock ;;
;;;;;;;;;;;;;;;

;; Code to mock the HEAD. Given a person id and its name, creates the
;; call chat and create the following
;;
;; (Evaluation
;;    (Predicate "name")
;;    (List
;;       (Concept person-id)
;;       (Concept name)))
;; (Evaluation
;;    (Predicate "say")
;;    (List
;;       (Concept person-id)
;;       (Sentence <sentence-id>)))
(define (mock-HEAD-chat person-id name message)
  (chat message)
  (sleep 1)                             ; you never know

  ;; Create name structure
  (Evaluation
     (Predicate "name")
     (List
        (Concept person-id)
        (Word name)))

  ;; Create say structure
  (let* ((sentence (cog-chase-link 'ListLink 'SentenceNode (Node message))))
    (Evaluation
       (Predicate "say")
       (List
          (Concept person-id)
          sentence))))

;;;;;;;;;;;;;;;
;; L2S rules ;;
;;;;;;;;;;;;;;;

;; Rule to turn something like
;;
;; (Evaluation
;;    (Predicate "name")
;;    (List
;;       (Concept "Person_215")
;;       (Word "Ben")))
;; (Evaluation
;;    (Predicate "say")
;;    (List
;;       (Concept "Person_215")
;;       (Sentence <sentence-1>)))
;; (InheritanceLink
;;    (Sentence <sentence-1>)
;;    (Concept <sentiment-1>))
;; ...
;; (Evaluation
;;    (Predicate "say")
;;    (List
;;       (Concept "Person_215")
;;       (Sentence <sentence-n>)))
;; (InheritanceLink
;;    (Sentence <sentence-n>)
;;    (Concept <sentiment-n>))
;;
;; into
;;
;; (Inheritance (stv s c)
;;    (Concept "Ben")
;;    (Concept "happy"))
;;
;; where s in the number of positive sentences divided by the number of
;; sentences, and c is the number of sentences divided by 800.

(define sentiment-sentence-to-person-l2s-vardecl
   (VariableList
      (TypedVariable
         (Variable "$person")
         (Type "ConceptNode"))
      (TypedVariable
         (Variable "$name")
         (Type "WordNode"))
      (TypedVariable
         (Variable "$sentence")
         (Type "SentenceNode"))
      (TypedVariable
         (Variable "$sentiment")
         (Type "ConceptNode"))))

(define sentiment-sentence-to-person-l2s-pattern
   (And
      (Evaluation
         (Predicate "name")
         (List
            (Variable "$person")
            (Variable "$name")))
      (Evaluation
         (Predicate "say")
         (List
            (Variable "$person")
            (Variable "$sentence")))
      (Inheritance
         (Variable "$sentence")
         (Variable "$sentiment"))))

(define sentiment-sentence-to-person-l2s-rewrite
   (ExecutionOutput
      (GroundedSchema "scm: sentiment-sentence-to-person-l2s-formula")
      (List
         (Variable "$person")
         (Variable "$name"))))

(define sentiment-sentence-to-person-l2s-rule
   (Bind
      sentiment-sentence-to-person-l2s-vardecl
      sentiment-sentence-to-person-l2s-pattern
      sentiment-sentence-to-person-l2s-rewrite))

;; Return the number of sentences from person P tagged with sentiment S
;;
;; More specifically count the number of matches
;;
;; (Evaluation
;;    (Predicate "say")
;;    (List
;;       P
;;       (Sentence <sentence-1>)))
;; (InheritanceLink
;;    (Sentence <sentence-1>)
;;    S))
;; ...
;; (Evaluation
;;    (Predicate "say")
;;    (List
;;       P
;;       (Sentence <sentence-n>)))
;; (InheritanceLink
;;    (Sentence <sentence-n>)
;;    S)
(define (count-sentiment-sentences P S)
  (let* (
         (V (Variable "$sentence"))
         (vardecl (TypedVariable V (Type "SentenceNode")))
         (say-pattern (Evaluation (Predicate "say") (List P V)))
         (query-pattern (And say-pattern (InheritanceLink V S)))
         (query (Get vardecl query-pattern))
         (results (cog-satisfying-set query)))
    (length (cog-outgoing-set results))))

(define (sentiment-sentence-to-person-l2s-formula Person Name)
  (let* (
         (K 800) ; parameter to convert from count to confidence
         ;; Count positive and negative sentences
         (pos-count (count-sentiment-sentences Person (Concept "Positive")))
         (neg-count (count-sentiment-sentences Person (Concept "Negative")))
         (total-count (+ pos-count neg-count))
         ;; Calculate strength and confidence
         (s (exact->inexact (/ pos-count total-count)))
         (c (exact->inexact (/ total-count K))))
    ;; (cog-logger-debug "[PLN-Reasoner] pos-count = ~a" pos-count)
    ;; (cog-logger-debug "[PLN-Reasoner] pos-count = ~a" neg-count)
    (Evaluation (stv s c)
       (Predicate "happy")
       (Concept (cog-name Name)))))

;; Rule to turn something like
;;
;; (InheritanceLink
;;    (ConceptNode "Ben@b0f3845c-9cfb-4b39-99a6-131004f6203d")
;;    (ConceptNode "Ben" (stv 0.029411765 0.0012484394))
;; )
;; (ImplicationLink
;;    (PredicateNode "crazy@1d08ff8b-4149-4362-97ef-9103a307a879")
;;    (PredicateNode "crazy" (stv 0.25 0.0012484394))
;; )
;; (EvaluationLink
;;    (PredicateNode "crazy@1d08ff8b-4149-4362-97ef-9103a307a879")
;;    (ListLink
;;       (ConceptNode "Ben@b0f3845c-9cfb-4b39-99a6-131004f6203d")
;;    )
;; )
;; (EvaluationLink
;;    (DefinedLinguisticPredicateNode "definite")
;;    (ListLink
;;       (ConceptNode "Ben@b0f3845c-9cfb-4b39-99a6-131004f6203d")
;;    )
;; )
;;
;; into
;;
;; (EvaluationLink (stv 1 0.1)
;;    (Predicate "crazy")
;;    (ConceptNode "Ben"))
;;
;; The 0.1 is largely arbitrary and convey the fact that we only have
;; limited evidences.
;;
;; To do well this rule should be replaced by an axioms relating the
;; cohesiveness of the involved predicate + PLN rules. THe axiom would
;; look like
;;
;; Implication
;;   VariableList
;;     TypedVariable
;;       Variable "$P"
;;       Type "Predicate"
;;     TypedVariable
;;       Variable "$X"
;;       Type "Concept"
;;     TypedVariable
;;       Variable "$Y"
;;       Type "Concept"
;;   And
;;     Evaluation
;;       Predicate "is-cohesive"
;;       Variable "$P"
;;     Evaluation
;;       Variable "$P"
;;       Variable "$X"
;;     Similarity
;;       Variable "$X"
;;       Variable "$Y"
;;   Evaluation
;;     Variable "$P"
;;     Variable "$X"
;;
;; Then PLN would use, as well as estimate the Similarities between
;; the arguments to produce some equivalent (but with better true
;; value estimate) outcome.
;;
;; We call these rule l2s, which stands for logic to
;; semantics. Eventually maybe these can be turned into a rule-base,
;; using the URE, but for now it's more like a hack.

(define unary-predicate-speech-act-l2s-vardecl
   (VariableList
      (TypedVariable
         (Variable "$element-instance")
         (Type "ConceptNode"))
      (TypedVariable
         (Variable "$element")
         (Type "ConceptNode"))
      (TypedVariable
         (Variable "$predicate-instance")
         (Type "PredicateNode"))
      (TypedVariable
         (Variable "$predicate")
         (Type "PredicateNode"))))

(define unary-predicate-speech-act-l2s-pattern
   (And
      (Inheritance
         (Variable "$element-instance")
         (Variable "$element"))
      (Implication
         (Variable "$predicate-instance")
         (Variable "$predicate"))
      (Evaluation
         (Variable "$predicate-instance")
         (List
            (Variable "$element-instance")))
      (EvaluationLink
         (DefinedLinguisticPredicateNode "definite")
         (ListLink
           (Variable "$element-instance")))))

(define unary-predicate-speech-act-l2s-rewrite
   (Evaluation (stv 1 0.1)
      (Variable "$predicate")
      (Variable "$element")))

(define unary-predicate-speech-act-l2s-rule
   (Bind
      unary-predicate-speech-act-l2s-vardecl
      unary-predicate-speech-act-l2s-pattern
      unary-predicate-speech-act-l2s-rewrite))

;;;;;;;;;;
;; Main ;;
;;;;;;;;;;

(define (pln-run)
  (define (pln-loop)
    ;; Apply l2s rules
    (let (
          (sentiment-sentence-to-person-l2s-results
           (cog-bind sentiment-sentence-to-person-l2s-rule))
          (unary-predicate-speech-act-l2s-results
           (cog-bind unary-predicate-speech-act-l2s-rule)))
      (cog-logger-debug "[PLN-Reasoner] sentiment-sentence-to-person-l2s-results = ~a" sentiment-sentence-to-person-l2s-results)
      (cog-logger-debug "[PLN-Reasoner] unary-predicate-speech-act-l2s-results = ~a" unary-predicate-speech-act-l2s-results))

    ;; Apply Implication direct evaluation (and put the result in
    ;; pln-inferred-atoms state)
    (let ((direct-eval-outputs (cog-bind implication-direct-evaluation-rule)))
      (State pln-inferred-atoms direct-eval-outputs)
      (cog-logger-debug "[PLN-Reasoner] pln-inferred-atoms = ~a"
                       direct-eval-outputs))

    ;; sleep a bit, to not overload the CPU too much
    (cog-logger-debug "[PLN-Reasoner] Sleep for a second")
    (sleep 1)

    ;; Loop
    (pln-loop))
  (begin-thread (pln-loop)))

(pln-run)
