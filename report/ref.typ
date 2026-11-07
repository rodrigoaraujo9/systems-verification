#import "@preview/codly:2.0.0" as codly

// Absolute size: codly 2.0 applies the 0.8em raw shrink inconsistently (diffs end up smaller).
#show raw: set text(size: 8.8pt)
#show raw.where(block: true): codly.new

#align(center)[
  #text(size: 18pt, weight: "bold")[
    Railway level crossing in mCRL2
  ]

  Diogo and Rodrigo Gomes de Araújo \
  up202510267, up202210267

  #text(size: 10pt)[#datetime.today().display("[month repr:long] [year]")]
]

#set par(
  justify: true,
  leading: 0.52em,
)

// Placeholder for screenshots. Swap `shot(...)` for `image("file.png", width: 100%)`.
#let shot(name) = rect(width: 100%, height: 3.5cm, stroke: (dash: "dashed"))[
  #align(center + horizon)[TODO: screenshot #name]
]
#let seq = math.class("binary", ".")
#let dia(x) = $lr(chevron.l #x chevron.r)$

= Introduction

This report was written for the first assignment of the _Systems Verification_ course at _Faculdade de Ciências da Universidade do Porto_ (FCUP). It presents a model of a railway level crossing, describing the interaction between a controller, a gate, and one or more trains that wish to cross. We then formalise a set of properties that verify its correctness and check them in mCRL2.

Processes are written in the CCS-style notation used in the course, and properties in process logic with regular expressions, where $-$ denotes any action, $-a$ any action other than $a$, and $;$ sequential composition (respectively `true`, `!a` and `.` in mCRL2).

= Task 1: One train

== 1a. Components

$
  "Train" & = "approach" seq "grant" seq "enter" seq "exit" seq "leave" seq "Train" \
   "Gate" & = "lower" seq "down" seq "raise" seq "up" seq "Gate" \
   "Ctrl" & = "approach" seq "lower" seq "down" seq "grant" seq "leave" seq "raise" seq "up" seq "Ctrl"
$

Each component is a single recursive loop, so all ordering constraints live in the controller: the grant is only issued once the gate reports `down`, and the gate is only raised after the train has signalled `leave`.

== 1b. Composition

Every interaction is modelled as a pair of complementary actions (e.g. `approach_train` and `approach_controller`) that `comm` merges into one synchronised action. `allow` then keeps only the synchronised results, so neither half can occur on its own:

```mcrl2
hide({ lower, down, grant, leave, raise, up },
allow({ approach, lower, down, grant, leave, raise, up, enter, exit },
comm({ approach_controller | approach_train -> approach, ... },
     TRAIN || GATE || CONTROLLER )));
```

For inspection we hide the internal handshakes with the gate, as well as `grant` and `leave`. We deliberately keep `approach` visible alongside `enter` and `exit`, so the observable behaviour still records a train arriving, entering and exiting.

== 1c. Inspection

#grid(
  columns: (1fr, 1fr),
  gutter: 1em,
  figure(shot("1_lts.png"), caption: [Full LTS]), figure(shot("1_lts_reduced.png"), caption: [Reduced LTS]),
)

// TODO: fill in from the tool (state/transition counts before and after reduction).
TODO: describe the full LTS and what remains in the reduced one.

== 1d. Properties

#table(
  columns: (auto, 1fr, auto),
  [*Property*], [*Formula*], [*Result*],
  [Safety],
  [$[-^*; "enter"; (-"exit")^*; "up"; -^*; "exit"] "false" and [-^*; "up"; (-"down")^*; "enter"] "false"$],
  [true],

  [Reachability], [$[-^*; "leave"] #dia($-^*; "raise"$) "true"$], [true],
  [Liveness], [$[-^*; "approach"] #dia($-^*; "exit"$) "true"$], [true],
  [Deadlock freedom], [$[-^*] #dia($-^*; "approach"$) "true"$], [true],
)

// TODO: up, down, leave and raise are hidden in init, so Safety and Reachability never match an action there.
// Check them on the model without hide, or say so here.
Safety has two parts: the gate never goes `up` while the train is between `enter` and `exit`, and after an `up` the train never enters before a `down`. With a single train every path follows the same cycle, so "can exit" in Liveness is the same as "must exit".

== 1e. Break it

// Not done yet: needs a copy of 1_spec.mcrl2 where the controller grants right after lower, without waiting for down.
TODO: the faulty variant, which property fails, the counterexample trace, and what went wrong.

= Task 2: Multiple trains

== 2a. Model with data

We chose the *queue model*. The controller stores a list $Q$ of the trains that approached and did not leave yet, in arrival order. It also stores `crossing` ($c$, `busy` from a `grant` until the matching `leave`) and its own view of the gate ($g$). The gate is the same as in Task 1. As in Task 1, the controller only talks to a train through `approach`, `grant` and `leave`: `enter` and `exit` are the train's own observable actions.

$
  "Train"(t) & = "approach"(t) seq "grant"(t) seq "enter"(t) seq "exit"(t) seq "leave"(t) seq "Train"(t) \
      "Gate" & = "lower" seq "down" seq "raise" seq "up" seq "Gate"
$

$
  "Ctrl"(Q, c, g) = & sum_(t in "Id") (t in.not Q) -> "approach"(t) seq "Ctrl"(Q triangle.l.small t, c, g) \
                  + & (Q != [thin] and g = "closed" and c = "free") -> "grant"("head"(Q)) seq "Ctrl"(Q, "busy", g) \
                  + & (Q != [thin] and c = "busy") -> "leave"("head"(Q)) seq "Ctrl"("tail"(Q), "free", g) \
                  + & (g = "open" and Q != [thin]) -> "lower" seq "Ctrl"(Q, c, "closing") \
                  + & (g = "closing") -> "down" seq "Ctrl"(Q, c, "closed") \
                  + & (g = "closed" and Q = [thin] and c = "free") -> "raise" seq "Ctrl"(Q, c, "opening") \
                  + & (g = "opening") -> "up" seq "Ctrl"(Q, c, "open")
$

$
  "System" = nabla_V (Gamma_C ("Train"(t_1) parallel dots parallel "Train"(t_N) parallel "Gate" parallel "Ctrl"([thin], "free", "open")))
$

where $Q triangle.l.small t$ appends $t$ at the end of $Q$ (`<|` in mCRL2).

*Why a queue.* With a set, `grant` could pick any waiting train, so one train could wait forever while another kept crossing. With a queue only the head can be granted, and a train that crosses and approaches again goes to the back. So no train is ever overtaken.

*Why the gate always finishes opening.* Once the controller decides to `raise`, the gate completes `up`, even if a train approached in the meantime. The controller then sees a non-empty queue and lowers it again. The train is not affected: it still needs `lower`, `down` and `grant` before it can enter.

*Invariant.* $Q$ always holds exactly the trains that did `approach` but not yet `leave`, in arrival order and without repetitions. It starts empty, `approach(t)` is the only step that adds $t$ (at the end), and `leave` the only one that removes a train (the head). The train that leaves is always the head, because only the head can be granted and nothing gets in front of it. Likewise, $c = "busy"$ holds exactly while one train is between `grant` and `leave`, because `grant` needs $c = "free"$. Two consequences follow:
- at most one train is between `grant` and `leave` at any time;
- `raise` needs $Q = [thin]$ and $c = "free"$, so the controller only decides to open when no train is between `approach` and `leave`.

== 2b. Properties

All for every $t in "Id"$ (and $t != t'$ in 2 and 5b):

// TODO: re-run all of these on the queue version and confirm the results.
#table(
  columns: (auto, 1fr, auto),
  [*Property*], [*Formula*], [*Result*],
  [1. Safety], [$[-^*; "enter"(t); (-"leave"(t))^*; "up"] "false"$], [true],
  [2. Mutual exclusion], [$[-^*; "enter"(t); (-"exit"(t))^*; "enter"(t')] "false"$], [true],
  [3. No premature raise], [$[-^*; "approach"(t); (-"leave"(t))^*; "raise"] "false"$], [true],
  [4. Deadlock freedom], [$[-^*] #dia($-^*; "approach"(t)$) "true"$], [true],
  [5a. Liveness (reach)], [$[-^*; "approach"(t); (-"enter"(t))^*] #dia($-^*; "enter"(t)$) "true"$], [true],
  [5b. Liveness (order)],
  [$[-^*; "approach"(t); (-"enter"(t))^*; "enter"(t'); \ (-"enter"(t))^*; "enter"(t')] "false"$],
  [true],

  [6. Road availability], [$[-^*] #dia($-^*; "up"$) "true"$], [true],
  [7. Infinite opening], [$[((-"up")^*; "up")^*] "true" and #dia($-$) "true"$], [true],
  [8. Non-vacuity],
  [$[-^*] #dia($-^*; "enter"(t)$) "true" and [-^*] #dia($-^*; "raise"$) "true" and [-^*] #dia($-$) "true"$],
  [true],
)

Properties 1--3 express the invariant directly. Property 3 checks `raise`, the controller's decision to open, as in the assignment ("the gate is never raised"); an `up` may still finish an opening started before the train arrived. Since a box formula holds trivially when its premise is unreachable, property 8 checks that the premises of 1--3 are in fact reachable, and that there is always a next step.

*Liveness and fairness (5).* Without fixpoints we cannot write "every `approach(t)` *must* be followed by `enter(t)`", so property 5 has two parts. The first (5a) says that while $t$ waits, `enter(t)` stays reachable. The second (5b) says that while $t$ waits, no other train enters twice, i.e. $t$ is overtaken at most $N - 1$ times. It is restricted to $t' != t$, because for $t' = t$ the pattern matches $t$'s own next trip ($"enter"(t)$, then later $"enter"(t)$ again), which is normal behaviour. With a set the second part fails, and we would need to assume fairness between trains. With the queue it holds, so a waiting train can only be delayed by the trains already ahead of it, and those are finite. We therefore need no fairness assumption for liveness, only that the system keeps running, which property 4 shows. The step from these two parts to "must enter" is our argument, not something the tool checks.

// TODO: [R*] true holds in every model, so 7 as written does not test anything.
*Infinite opening (7).* Fairness towards the road cannot come from the controller. If trains keep arriving so that $Q$ is never empty, `raise` never happens and the gate stays closed. In practice, cars wait for as long as the train traffic lasts. Avoiding this would mean holding trains back to let cars through, which changes what the system is for. So this property depends on an assumption about the trains: that there are moments when none is approaching. Property 6 shows that opening is always still possible.

== 2c. Break it: a family of bugs

// Not done yet: each bug needs its own copy of 2_spec.mcrl2, then run all 2b properties on it.
TODO: naive raise, missed increment, off-by-one. For each: the change, which properties fail, the shortest counterexample and the scenario in words.

== 2d. State space

#table(
  columns: (auto, 1fr, 1fr, 1fr, 1fr),
  [*N*], [*States*], [*Transitions*], [*States (red.)*], [*Trans. (red.)*],
  [1], [TODO], [TODO], [TODO], [TODO],
  [2], [TODO], [TODO], [TODO], [TODO],
  [3], [TODO], [TODO], [TODO], [TODO],
  [4], [TODO], [TODO], [TODO], [TODO],
  [5], [TODO], [TODO], [TODO], [TODO],
  [6], [TODO], [TODO], [TODO], [TODO],
)

// TODO: check this against the numbers once the table is filled, and re-check the star/symmetry remark on the queue version.
The state space grows quickly with $N$: each train moves through its own cycle independently, and the controller stores not just which trains are waiting but also their order. We could still generate it for $N = 6$. The LTS has a star shape in which $N - 1$ arms always have the same shape. This reflects the symmetry between trains: they only differ by their identifier, so permuting identifiers maps the system onto itself.

= Conclusion

With a single train, the fixed order of actions is enough to guarantee safety. With $N$ trains, the controller must track which trains are near ($Q$) and whether the crossing is occupied ($c$), and these two invariants are what make safety, mutual exclusion and no premature raising hold. Keeping $Q$ as a queue also gives liveness per train without a fairness assumption. Fairness only remains an issue for the road, which stays closed for as long as trains keep arriving.

// TODO: add what Break it (1e, 2c) showed, once done.
