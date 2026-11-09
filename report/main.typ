#import "@preview/codly:2.0.0" as codly
// Absolute size: codly 2.0 applies the 0.8em raw shrink inconsistently (diffs end up smaller).
#show raw: set text(size: 8.8pt)
#show raw.where(block: true): codly.new

#let filler(name) = rect(width: 100%, height: 3.5cm, stroke: (dash: "dashed"))[
  #align(center + horizon)[TODO: screenshot #name]
]
#let seq = math.class("binary", ".")
#let dia(x) = $lr(chevron.l #x chevron.r)$
// Clickable reference to a Task 2 property row.
#let pr(id, body: none) = link(label("prop-" + id), if body == none { id } else { body })

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
hide({ lower, grant },
allow({ approach, lower, down, grant, leave, raise, up, enter, exit },
comm({ approach_controller | approach_train -> approach, ... },
     TRAIN || GATE || CONTROLLER )));
```

For inspection, we split the actions into messages and physical events. Messages are internal handshakes between the components and cannot be observed from the outside, so we hide them:
- *`lower`:* the command to the gate;
- *`grant`:* the permission to cross.

The messages `leave` and `raise` stay visible, because the properties below refer to them.

Physical events, on the other hand, are what someone standing near the crossing would observe, so they remain visible:
- *`approach`:* the train arriving;
- *`enter`, `exit`:* being on the crossing;
- *`down`, `up`:* the gate reaching its position.

== Inspection

#grid(
  columns: (1fr, 1fr),
  gutter: 1em,
  [#figure(image("./assets/normal.png"), caption: [Full LTS]) <fig:full-lts>],
  [#figure(image("./assets/branching_bisimulation.png"), caption: [Reduced LTS]) <fig:reduced-lts>],
)

// TODO: confirm the state counts with the tool.
The full LTS (@fig:full-lts) is a single cycle of 9 states, two of whose transitions are $tau$ (the hidden messages). None of these $tau$-steps removes a choice, so branching bisimulation collapses them, leaving a cycle of 7 states made only of the physical events (@fig:reduced-lts). This is the externally observable behaviour of the train passing through the crossing.

== Properties

#table(
  columns: (auto, 1fr, auto),
  [*Property*], [*Formula*], [*Result*],
  [#metadata(none)<t1-safety>Safety],
  [$[-^*; "enter"; (-"exit")^*; "up"] "false" and [(-"down")^*; "enter"] "false" and [-^*; "up"; (-"down")^*; "enter"] "false"$],
  [true],

  [#metadata(none)<t1-reachability>Reachability], [$[-^*; "leave"] #dia($-^*; "raise"$) "true"$], [true],
  [#metadata(none)<t1-liveness>Liveness], [$[-^*; "approach"] #dia($-^*; "exit"$) "true"$], [true],
  [#metadata(none)<t1-deadlock>Deadlock freedom], [$[-^*] #dia($-^*; "approach"$) "true"$], [true],
)

The model satisfies all four properties.

- For #link(<t1-safety>)[_safety_], the train is never on the crossing while the gate is open: once a train has entered (`enter`), the gate cannot be raised (`up`) until the train exits (`exit`). Furthermore, a train can only enter if the gate has been lowered (`down`) since it was last raised, ensuring that the gate remains closed whenever the train is on the crossing.

- For #link(<t1-reachability>)[_reachability_], from any reachable state, the gate can eventually be raised (`raise`), allowing the system to return to its open state.

- For #link(<t1-liveness>)[_liveness_], whenever a train approaches (`approach`), it can eventually exit (`exit`), ensuring that it is not permanently prevented from completing its passage.

- Finally, for #link(<t1-deadlock>)[_deadlock freedom_], from any reachable state, a new train can eventually approach (`approach`), meaning the system can continue making progress and the cycle can restart.

== Broken Variant

In the faulty variant (@fig:broken-lts), the controller issues the grant immediately after ordering the gate to lower, without waiting for the `down` acknowledgement:

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
) <fig:broken-lts>

The #link(<t1-safety>)[safety property] $[(not "down")^* dot "enter"] "false"$ (no `enter` unless a `down` occurred since the last `up`) fails with the following counterexample:

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

All properties are quantified over $t in "Id"$, and some with $t in "Id"$ s.t. $t != t'$ as well.

// TODO: confirm all results on the current model (queue + leave-only controller).
#table(
  columns: (auto, 1fr, auto),
  [*Property*], [*Formula*], [*Result*],
  [#metadata(none)<prop-1>1. Safety],
  [$[-^*; "enter"(t); (-"exit"(t))^*; "up"] "false" and [(-"down")^*; "enter"(t)] "false" and [-^*; "up"; (-"down")^*; "enter"(t)] "false"$],
  [true],

  [#metadata(none)<prop-2>2. Mutual exclusion], [$[-^*; "enter"(t); (-"exit"(t))^*; "enter"(t')] "false"$], [true],
  [#metadata(none)<prop-3>3. No premature raise], [$[-^*; "approach"(t); (-"leave"(t))^*; "raise"] "false"$], [true],
  [#metadata(none)<prop-4>4. Deadlock freedom], [$[-^*] #dia($-^*; "approach"(t)$) "true"$], [true],
  [#metadata(none)<prop-5a>5a. Liveness (reach)],
  [$[-^*; "approach"(t); (-"enter"(t))^*] #dia($-^*; "enter"(t)$) "true"$],
  [true],

  [#metadata(none)<prop-5b>5b. Liveness (order)],
  [$[-^*; "approach"(t); (-"enter"(t))^*; "enter"(t'); \ (-"enter"(t))^*; "enter"(t')] "false"$],
  [true],

  [#metadata(none)<prop-6>6. Road availability], [$[-^*] #dia($-^*; "up"$) "true"$], [true],
  [#metadata(none)<prop-7>7. Infinite opening],
  [$[ "approach"(t_1); "approach"(t_2); \
    (-"up")^*; "leave"(t_1); "approach"(t_1); \
    (-"up")^*; "leave"(t_2); "approach"(t_2)] "false"$],
  [false],

  [#metadata(none)<prop-8>8. Non-vacuity],
  [$[-^*] #dia($-^*; "enter"(t)$) "true" and [-^*] #dia($-^*; "raise"$) "true" and [-^*] #dia($-$) "true"$],
  [true],
)

=== Safety (#pr("1")--#pr("3"))

The first three properties ensure that the crossing is used safely.
A train can only enter when the gate is fully down (#pr("1")), and only
one train can occupy the crossing at a time (#pr("2")). The gate can only
start opening when the crossing is free and no trains are waiting.
If a train approaches while the gate is opening, the gate must
close again before granting access (#pr("3")).

=== Liveness (#pr("4")--#pr("5a", body: "5"))

These properties ensure that the system continues to make progress.
A train can always approach the crossing (#pr("4")), and every waiting
train remains able to enter (#pr("5a")). The FIFO queue also prevents
indefinite overtaking, since no other train can enter twice before
the waiting train gets its turn (#pr("5b")). Assuming the system continues
to execute actions, every waiting train eventually enters.

=== Availability (#pr("6")--#pr("8"))

The gate can always eventually return to the open position (#pr("6")).
However, continuous train arrivals may prevent the queue from
becoming empty, so recurring openings cannot be guaranteed (#pr("7")).
We present a counterexample: $t_1$ and $t_2$ keep re-approaching,
so the queue never empties.
Finally, non-vacuity (#pr("8")) ensures that train entry, gate raising
and system transitions are reachable, making the verification
meaningful.

== Broken Variant

Three faulty variants are introduced to test whether the verified properties detect incorrect controller behaviour.

=== Naive Raise

The controller moves to the `opening` state immediately after a train leaves, without checking whether other trains are still waiting and without performing the `raise` handshake with the gate:

```diff-mcrl2
   leave_controller(head(queue))
-  . CONTROLLER(tail(queue), free, gate)
+  . CONTROLLER(tail(queue), free, opening)
```

The liveness property (#pr("5a")) fails with the following counterexample:

$"approach"(t_1) seq "lower" seq "down" seq "grant"(t_1) seq "enter"(t_1) seq "approach"(t_2) seq "exit"(t_1) seq "leave"(t_1)$

After $"leave"(t_1)$ the controller is in the `opening` state with $t_2$ still in the queue. It now only offers `up`, but the gate still waits for `raise`, so the two can never synchronise. The gate stays closed, `grant` requires an open-to-closed cycle that never happens again, and $t_2$ can no longer enter. This is the same behaviour for every train that is queued, and once all trains are queued the system deadlocks. Hence properties #pr("4") (deadlock freedom), #pr("5a") (liveness), #pr("6") (road availability) and #pr("8") (non-vacuity, since `raise` is unreachable) fail. Property #pr("3") still holds, as `raise` never occurs. Property #pr("7") holds, as the trains block before the counterexample can occur.

=== Missed Increment

An approaching train is not added to the queue when another train is already crossing:

```diff-mcrl2
   approach_controller(t)
-  . CONTROLLER(queue <| t, crossing, gate)
+  . CONTROLLER(if(crossing == busy, queue, queue <| t), crossing, gate)
```

The liveness property (#pr("5a")) fails with the following counterexample:

$"approach"(t_1) seq "lower" seq "down" seq "grant"(t_1) seq "enter"(t_1) seq "approach"(t_2)$

Since $t_2$ is not recorded in the queue, the controller never grants it access. The train stays blocked at its `grant` action, so its entry is no longer reachable, even after $t_1$ leaves. The same happens to every train that approaches while the crossing is busy. The train that is crossing is never lost, so the system does not deadlock, but the lost trains can never approach again. Hence properties #pr("3") (no premature raising, since the gate is raised once $t_1$ leaves while $t_2$ is still waiting), #pr("4") (deadlock freedom), #pr("5a") (liveness), #pr("7") (infinite opening, since trains that approach while the crossing is free are still queued) and #pr("8") (non-vacuity, since the entry of a lost train is unreachable) fail. Properties #pr("1"), #pr("2") and #pr("6") still hold, as the behaviour of the trains that are queued is unchanged and the gate can still open once the queue is empty.

=== Off-by-One

The controller incorrectly updates the crossing state when a train leaves, keeping it marked as busy even though the crossing is empty:

```diff-mcrl2
   leave_controller(head(queue))
-  . CONTROLLER(tail(queue), free, gate)
+  . CONTROLLER(tail(queue), busy, gate)
```

The road availability property (#pr("6")) fails with the following counterexample:

$"approach"(t_1) seq "lower" seq "down" seq "grant"(t_1) seq "enter"(t_1) seq "exit"(t_1) seq "leave"(t_1)$

Although $t_1$ has left the crossing and the queue is empty, the controller still considers the crossing busy. Both `grant` and `raise` require $c = "free"$, so neither can ever happen again, and the gate stays closed. A train $t_2$ that approaches afterwards is queued but never granted access, since the head of the queue waits for a `leave` that its train can never produce. Once every train is stuck in the queue, no train can approach any more and the system deadlocks. Hence properties #pr("4") (deadlock freedom), #pr("5a") (liveness), #pr("6") (road availability) and #pr("8") (non-vacuity, since `raise` is unreachable) fail. Properties #pr("1") to #pr("3") and #pr("5b") still hold, because neither `up` nor a second `enter` ever occurs. Property #pr("7") holds, as the trains block before the counterexample can occur.

== State Space and Abstraction


#grid(
  columns: (1fr, 1fr),
  gutter: 1em,
  [#figure(image("./assets/normal_2.png"), caption: [Full LTS]) <fig:full-lts-2>],
  [#figure(image("./assets/branching_bisimulation_2.png"), caption: [Reduced LTS]) <fig:reduced-lts-2>],
)

For $N = 1$ to $6$ the full LTS (@fig:full-lts-2) has 10, 31, 108, 451, 2278 and 13695 states, respectively. The reduced LTS (@fig:reduced-lts-2) has 8, 23, 78, 323, 1628 and 9783. Both LTSs grow quickly with $N$, because the trains interleave freely and the controller keeps a queue of waiting trains.

The reduction comes from hiding the `lower` and `grant` handshakes, as in Task 1. These are internal messages, not events visible at the crossing. After hiding they become $tau$ steps, and the reduction merges the states that were connected only by these steps. This removes ≈26.5% of the states, and the gain stays similar as $N$ grows, since the reduced LTS is ≈73.5% of the full one on average.

The trains are symmetric. They all run the same process, and the controller serves them in FIFO order, so swapping the IDs of two trains maps the LTS onto itself. The reduction preserves this symmetry, because the actions of each train keep their own labels and are never merged with those of another train.

= Conclusion

In this assignment, we modelled a railway level crossing with both a single train and multiple trains, using mCRL2 to verify its behaviour. We saw how the controller coordinates the trains and the gate to ensure safe crossing and avoid conflicts. By testing faulty variants, we also understood how small mistakes in the controller can lead to safety and liveness problems, and how counterexamples help identify them. Overall, this work gave us a better understanding of how formal verification can be used to detect edge cases and prevent errors in concurrent systems.
