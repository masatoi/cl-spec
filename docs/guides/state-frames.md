# Observe allowed state changes

Use `:modifies` on a function contract to state which keys the target may
change inside each observer's scope. The clause checks additions, removals and
changes to values.

```lisp
(asdf:load-system "cl-spec")

(defvar *accounts* (make-hash-table :test #'equal))

(cl-spec:register-hash-table-state-observer
 :accounts (lambda () *accounts*) :version 1)

(defun credit! (account-id amount)
  (incf (gethash account-id *accounts* 0) amount))

(cl-spec:defspec-function credit!
  (:args (account-id keyword) (amount (range integer 1 10)))
  (:returns integer)
  (:modifies (:accounts account-id)))

(cl-spec:call-check-data (cl-spec:check-call 'credit! '(:primary 5)))
```

Each group has an observer name followed by zero or more allowed-key
expressions. The expressions see the arguments and any `:capture` bindings.
A group with no keys requires the observer's entire scope to stay unchanged.
Groups for the same observer share one pair of snapshots and their allowed
keys are combined. Keys are compared with `equal`.

Use `(:each form)` in a key group to allow every member of a list computed
at runtime. The checker evaluates the form once before the call. It accepts
a finite proper list, with `nil` contributing zero keys. A malformed value
produces a contract error in the `:allowed-keys` stage. An ordinary key
expression can still contribute a single list-valued key.

```lisp
(defun credit-all! (ids amount)
  (dolist (id ids ids)
    (incf (gethash id *accounts* 0) amount)))

(cl-spec:defspec-function credit-all!
  (:args (ids (list-of keyword)) (amount (range integer 1 10)))
  (:returns (list-of keyword))
  (:modifies (:accounts (:each ids))))
```

After preconditions and case selection, the checker evaluates the allowed keys
and takes a snapshot immediately before the target. After a passing outcome
(including an expected error), the checker compares state and then runs any
`:state-post` forms. Earlier failures retain their own classification.

The first forbidden change produces `:failed` with reason
`:state-postcondition` and phase `:state-post`. Its `:state :frame` evidence
names the observer and changed key. The `:before` and `:after` records
distinguish a missing entry via `(:present nil)` from a present value via
`(:present t :value VALUE)`. The check saves these records before cleanup.
An observer callback or data error produces `:contract-error` and names the
operation that failed.

## Register an observer for application state

```lisp
(cl-spec:register-state-observer
 :rows :version 1
 :snapshot 'read-row-snapshot
 :compare 'changed-row-ids
 :project 'project-row)
```

- `snapshot ()` returns an independent view of the entire relevant scope.
  The snapshot can contain application-specific objects.
- `compare (before after)` returns a finite list of changed keys. Its order
  chooses which violation is reported when multiple changes are forbidden.
- `project (snapshot key)` returns the printable value and a second boolean
  giving presence, like `gethash`. Only a forbidden change is projected.

Observer operations must leave the snapshots and observed state intact.
Keys must survive copying under `equal`. Each saved key and projected value
must fit the bounded AV1 codec (2,048 nodes, depth 32, 16,384 characters).
The supplied in-memory observer takes an `equal` hash table and snapshots
its keys and values using the same bounds. It distinguishes absent keys from
stored NIL values.

The contract captures its registry's observer registrations when the
contract is declared. To adopt a replacement observer, evaluate the
`defspec-function` declaration again. The digest covers the frame expressions, the observer name,
version and declared callback identities. For anonymous callbacks use
`:source` to supply stable declaration data. With an anonymous callback
and no source, the digest is incomplete. Bump the version when the behavior
or scope of an observer changes, including changes in a helper it calls.

A frame uses the ordinary state-observing contract rules. A recipe-backed
fixture can provide independent state for shrinking, seed replay and saved
counterexamples. Runtime instrumentation refuses state-observing contracts.
