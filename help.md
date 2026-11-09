I’ll compare the report against every file in `1/` and `2/`, checking the models, formulas, results, counterexamples, and state counts for inconsistencies.

I found substantive mismatches: Task 1’s safety formula differs from its `.mcf` file, and Task 2’s “infinite opening” formula does not establish recurring openings. Some faulty-variant claims also conflict with the formulas. I found the installed mCRL2 tools and will check the results and state counts directly.

The original models return `true` for every saved property, and all reported state counts match. The problems are in what some results are said to prove: property 7 stays `true` in all three literal faulty variants, property 8 fails in “Missed Increment,” and that variant’s printed diff cannot produce its stated counterexample. The Task 2 figures also appear to be swapped.

I’ve now read **every file in `1/` and `2/`**, compared them with the report, and run mCRL2 on the original models and reconstructed faulty variants. **They are not fully coherent.**

The concrete issues are:

1. **Task 1’s safety formula differs from the code.** The [report](/Users/rodrigoaraujo/Desktop/github/systems-verification/report/main.typ:93) adds a first-cycle check and removes a trailing condition present in [Safety.mcf](/Users/rodrigoaraujo/Desktop/github/systems-verification/1/properties/Safety.mcf:1). Both pass the original model, but the report’s first-cycle counterexample does not demonstrate failure of the saved formula; that formula detects the problem on a later cycle.

2. **Task 1’s reachability check passes vacuously.** [The model hides `leave` and `raise`](/Users/rodrigoaraujo/Desktop/github/systems-verification/1/1_spec.mcrl2:33), while [Reachability.mcf](/Users/rodrigoaraujo/Desktop/github/systems-verification/1/properties/Reachability.mcf:1) checks those action names. There are no visible `leave` transitions to trigger its obligation. Its `true` result therefore does not establish the report’s claim about raising the gate.

3. **Property 7 does not check infinite opening.** In [the formula file](/Users/rodrigoaraujo/Desktop/github/systems-verification/2/properties/Road%20avaliability%20infinite%20opening.mcf:2), `[R]true` always holds, and `<true>true` only requires an initial transition. It returns **true in all three printed faulty variants**, contrary to the report’s claims that it fails.

4. **“Missed Increment” describes a different change from its diff.** The [printed diff](/Users/rodrigoaraujo/Desktop/github/systems-verification/report/main.typ:233) drops **every** approaching train from the queue, rather than only dropping trains while the crossing is busy. Consequently, the first train never receives a grant, and the stated counterexample trace is impossible.

5. **“Missed Increment” incorrectly says property 8 holds.** [Non-vacuity.mcf](/Users/rodrigoaraujo/Desktop/github/systems-verification/2/properties/Non%20vacuity.mcf:5) requires reachability from **every reachable state**, not just initially. It returns **false**, both for the printed diff and for the conditional mutation described in the prose.

6. **Task 2’s safety explanation overstates properties 1 and 3.** [Property 1](/Users/rodrigoaraujo/Desktop/github/systems-verification/report/main.typ:168) forbids `up` between `enter` and `leave`; it does not check that the gate was down before entry. Property 3 forbids `raise` while a train waits; it does not itself check closing again before granting access. The controller implements those behaviours, but these formulas do not establish all of them.

7. **Task 2’s LTS pictures are swapped.** The [figure labelled “Full LTS”](/Users/rodrigoaraujo/Desktop/github/systems-verification/report/main.typ:269) shows merged states from the reduced graph; the picture labelled “Reduced LTS” shows the unreduced graph.

8. **The reduction percentages are wrong.** The [reported state counts](/Users/rodrigoaraujo/Desktop/github/systems-verification/report/main.typ:273) are correct, but the reductions are **20%, 25.81%, 27.78%, 28.38%, 28.53%, and 28.57%**, rather than approximately 26.5% throughout.

What checks out: the controller equations match the implementations, every saved property returns `true` on its original model, Task 1 reduces from **9 to 5 states**, and all six Task 2 state-count pairs match. The report also compiles.

I haven’t changed the report or model files during this audit.
