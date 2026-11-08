#import "@preview/codly:2.0.0" as codly
// Absolute size: codly 2.0 applies the 0.8em raw shrink inconsistently (diffs end up smaller).
#show raw: set text(size: 8.8pt)
#show raw.where(block: true): codly.new

#let filler(name) = rect(width: 100%, height: 3.5cm, stroke: (dash: "dashed"))[
  #align(center + horizon)[TODO: screenshot #name]
]
#let seq = math.class("binary", ".")
#let dia(x) = $lr(chevron.l #x chevron.r)$

#set page(numbering: "1")

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

// Display equations: left-aligned with a small indent instead of centred.
#show math.equation.where(block: true): it => pad(left: 1em, align(left, it))

= Introduction

This report was written for the first assignment of the _Systems Verification_ course at _Faculdade de Ciências da Universidade do Porto_ (FCUP). It presents a model of a railway level crossing, describing the interaction between a controller, a gate, and one or more trains that wish to cross. We then formalise a set of properties that verify its correctness and check them in mCRL2.

= Task 1

In this task we modelled a single train passing through the crossing.

== Components

The model contains the following three processes.

$
       "Train" & = "approach" dot "grant" dot "enter" dot "exit" dot "leave" dot "Train" \
        "Gate" & = "lower" dot "down" dot "raise" dot "up" dot "Gate" \
  "Controller" & = "approach" dot "lower" dot "down" dot "grant" dot "leave" dot "raise" dot "up" dot "Controller"
$

Each one consists of a loop over a finite set of actions. The `Controller` enforces the ordering between the `Gate` and the `Train`'s actions. It allows the train to enter (`grant`) after the gate is `down` and `raise` the gate after the train `leave`s.

== Composition

Every interaction is modelled as a pair of complementary actions (e.g. `approach_train` and `approach_controller`) that `comm` merges into one synchronised action. `allow` then ensures they occur strictly simmultaneously.

```mcrl2
hide({ lower, grant, leave, raise },
allow({ approach, lower, down, grant, leave, raise, up, enter, exit },
comm({ approach_controller | approach_train -> approach, ... },
     TRAIN || GATE || CONTROLLER )));
```

For inspection, we split the actions into messages and physical events. Messages are internal handshakes between the components and cannot be observed from the outside, so we hide them:
- *`lower`, `raise`:* the commands to the gate;
- *`grant`:* the permission to cross;
- *`leave`:* the train's notification that it left.

Physical events, on the other hand, are what someone standing near the crossing would observe, so they remain visible:
- *`approach`:* the train arriving;
- *`enter`, `exit`:* being on the crossing;
- *`down`, `up`:* the gate reaching its position.

== Inspection

#grid(
  columns: (1fr, 1fr),
  gutter: 1em,
  figure(image("./assets/normal.png"), caption: [Full LTS]),
  figure(image("./assets/branching_bisimulation.png"), caption: [Reduced LTS]),
)

// TODO: confirm the state counts with the tool.
The full LTS is a single cycle of 9 states, four of whose transitions are $tau$ (the hidden messages). None of these $tau$-steps removes a choice, so branching bisimulation collapses them, leaving a cycle of 5 states made only of the physical events:

$ "approach" -> "down" -> "enter" -> "exit" -> "up" -> "approach" $

This is the externally observable behaviour of the train passing through the crossing.

== Properties

#table(
  columns: (auto, 1fr, auto),
  [*Property*], [*Formula*], [*Result*],
  [Safety],
  [$[-^*; "enter"; (-"exit")^*; "up"] "false" and [(-"down")^*; "enter"] "false" and [-^*; "up"; (-"down")^*; "enter"] "false"$],
  [true],

  [Reachability], [$[-^*; "leave"] #dia($-^*; "raise"$) "true"$], [true],
  [Liveness], [$[-^*; "approach"] #dia($-^*; "exit"$) "true"$], [true],
  [Deadlock freedom], [$[-^*] #dia($-^*; "approach"$) "true"$], [true],
)

The model satisfies four properties, and all of them hold. For _safety_, the train is never on the crossing while the gate is open: once a train has entered (`enter`), the gate cannot go up (`up`) until the train exits (`exit`), and a train can only enter if the gate has gone down (`down`) since it was last raised, which together guarantee the gate is closed whenever the train is on the crossing. For _reachability_, from any reachable state the gate can eventually be raised (`raise`), so the system can always return to its open state. For _liveness_, whenever a train approaches, it can eventually exit, so an approaching train is never blocked forever. Finally, for _deadlock freedom_, from any reachable state a new train can eventually approach (`approach`), so the system never gets stuck and the cycle can always restart.

== Broken Variant

In the faulty variant, the controller issues the grant immediately after ordering the gate to lower, without waiting for the `down` acknowledgement:

```diff-mcrl2
   approach_controller
-  . lower_controller . down_controller
-  . grant_controller
+  . lower_controller . grant_controller
+  . down_controller
```

#figure(
  image("./assets/broken.png", width: 50%),
  caption: [Broken LTS],
)

The safety property $[(not "down")^* dot "enter"] "false"$ (no `enter` unless a `down` occurred since the last `up`) fails with the following counterexample:

$"approach" seq "lower" seq "grant" seq "enter"$

Since `lower` and `grant` are hidden, the observable trace is just `approach, enter`: the train enters with no `down` before it, so the formula is violated. The gate process is still waiting to fire `down_gate`, because after `lower` the train and gate run independently and the train wins the race.

= Task 2

In this task the model allows multiple trains to pass through the crossing one at a time.

== Model with data

$"Train"(t)$ and $"Gate"$ are the same as in Task 1, with the train's actions carrying its identity. The controller keeps a queue $Q$ of the trains that approached and did not leave yet, whether the crossing $c$ is `busy` or `free`, and the gate state $g$:

// Slightly smaller so the longest line fits the page width.
#[
  #set text(size: 0.94em)
  $
    "Controller"(Q, c, g) = & sum_(t in "Id") (t in.not Q) -> "approach"(t) seq "Controller"(Q triangle.l.small t, c, g) \
    & #h(0.6em) + (Q != [thin] and g = "closed" and c = "free") -> "grant"("head"(Q)) seq "Controller"(Q, "busy", g) \
    & #h(0.6em) + (Q != [thin] and c = "busy") -> "leave"("head"(Q)) seq "Controller"("tail"(Q), "free", g) \
    & #h(0.6em) + (g = "open" and Q != [thin]) -> "lower" seq "Controller"(Q, c, "closing") \
    & #h(0.6em) + (g = "closing") -> "down" seq "Controller"(Q, c, "closed") \
    & #h(0.6em) + (g = "closed" and Q = [thin] and c = "free") -> "raise" seq "Controller"(Q, c, "opening") \
    & #h(0.6em) + (g = "opening") -> "up" seq "Controller"(Q, c, "open")
  $
]

where $Q triangle.l.small t$ appends $t$ to the end of $Q$. We chose a queue over a set so that only the first train in line can be granted. No train is overtaken, which matters for liveness.

*Invariant.* $Q$ always holds exactly the trains that approached but did not leave yet: `approach(t)` is the only step that adds a train and `leave` the only one that removes it. $c$ is `busy` exactly while one train is between `grant` and `leave`. Since `grant` needs $c = "free"$, only one train crosses at a time, and since `raise` needs $Q$ empty and $c = "free"$, the gate is never raised while a train is near.

== Properties

All properties are quantified over $t in "Id"$, and over $t' != t$ where $t'$ appears.

// TODO: confirm all results on the current model (queue + leave-only controller).
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

Property 3 checks `raise`, the controller's decision to open. Once raised, the gate always finishes with `up`, even if a train approached meanwhile; the controller then lowers it again before any `grant`. Property 8 makes sure the premises of 1--3 are reachable, so they do not hold vacuously.

*Liveness and fairness (5).* Without fixpoints we cannot say that `enter(t)` *must* happen, so we check two things: `enter(t)` stays reachable while $t$ waits (5a), and no other train enters twice in the meantime (5b) ($t' != t$, since $t$'s own next trip is normal). With a set, a train could be overtaken forever and we would need to assume fairness between trains. The queue removes that: a waiting train is overtaken at most $N - 1$ times, so we only assume the system keeps running (property 4).

// TODO: [R*] true holds in every model, so 7 as written does not test anything.
*Infinite opening (7).* The controller cannot guarantee this. If trains keep arriving, $Q$ never empties and the gate never opens. A counterexample would mean that, under heavy traffic, cars wait for as long as trains keep coming. This is a loss of availability, not of safety, and property 6 shows that opening is always still possible.

== Broken Variant

= Conclusion
