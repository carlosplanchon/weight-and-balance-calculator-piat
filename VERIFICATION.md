# How this calculator is verified

This document records what has been checked in this tool, how, and what the
result does and does not entitle anyone to conclude. It exists because the
README carries a disclaimer, and a disclaimer only says what a tool does not
promise. This says what was actually done.

## What this does not establish

Read this part first, because everything below is easy to mistake for something
it is not.

Nothing here has been checked against an aircraft. There is no flight test, no
weighing, no independent review, and no approval of any kind. Verification here
means one thing only: **the figures in the code were compared against the
figures the handbooks publish, and the behaviour built on them was compared
against what those figures imply.** A calculation can be faithful to a handbook
and still be the wrong thing to fly on, because the handbook describes an
aircraft in a condition yours may not be in.

The tool also has no way to know whether the numbers you give it are true. It
checks that a fleet file is well formed and internally coherent. It cannot check
that an empty weight matches the aircraft parked outside.

Use the official POH and the aircraft's current weight and balance
documentation. Ask a qualified instructor. That is not boilerplate: it follows
from what is written below.

## Where the figures come from

Three sources, in a fixed order of authority.

**The handbook, for the type.** Two documents:

- ALPHA Trainer: POH-162-00-40-001, rev. A07
- ALPHA Trainer PRO: POH-162-00-40-003, rev. B01

Everything that belongs to the type lives in the code: arms, tank capacity,
unusable fuel, fuel density, the occupancy limits, the CG envelope, MTOM.

**That aircraft's own current approved documentation, for the airframe.** Empty
weight and empty arm belong to the individual aircraft, not to the type. POH
section 6.2 marks them with an asterisk and says they are to be obtained from
the applicable weight and balance manifest, which is the usual document and the
one the fleet file is built around.

The same reasoning reaches the CG limits, which is why an entry may declare its
own and have them win over the type's envelope. A handbook publishes the
envelope of a *type*; equipment and modifications belong to one *airframe*, and
what records them is that aircraft's own paperwork, whether that is its manifest
or an approved supplement. The rule is therefore aircraft-specific approved
documentation over generic type data, rather than one named document beating
another, and each entry records which document its figures came from. An
aircraft that declares no limits of its own inherits the type's, and the
interface says so rather than letting the figure pass as if it were the
aircraft's.

**The fleet file, for nothing at all.** It is data the deployment supplies, and
the code treats it the way it treats a localStorage payload: nothing in it is
trusted, a malformed entry is dropped and counted rather than repaired, and a
file that cannot be read leaves the calculator usable and saying why.

Between those sources and the verdict there is no arithmetic that does not have
to be there. Limits are read from the aircraft entry, which publishes both unit
systems, rather than converted from one into the other, so switching between
kilograms and pounds does not put a rounding step between the handbook and the
envelope a point is judged against.

## The suite

344 assertions across seven modules, all running in the browser against the same
code the page uses.

| Module | Assertions | What it is for |
| --- | ---: | --- |
| Pipistrel Alpha W&B Calculator | 116 | Worked examples, including the four POH 6.2 sample calculations, and the pending gate that keeps a half-filled form from producing a verdict |
| Fleet file | 65 | Format validation, rejection of malformed entries, behaviour with no file at all |
| POH source data | 45 | Every constant written out a second time against the handbook it comes from |
| Envelope verdict | 46 | That the CG and weight limits actually refuse what they are supposed to refuse |
| Load limits | 22 | The same, for seat, cabin, baggage and minimum pilot |
| Invariants (grid sweeps) | 9 | Relationships that must hold at every point of a grid spanning the supported ranges |
| Persistence | 41 | Session restore, corrupt payloads, the data age clock |

Four ideas shape how those modules are split.

**A constant is checked against its source, not against itself.** Every figure
taken from a handbook is written out a second time in the suite, next to the
document and section it comes from. This is the only kind of check that catches
a value which is correct in form and wrong in fact. A transposed digit that
preserves the order of a table breaks no relationship and passes every worked
example that does not happen to land on it.

**Checking what a limit says is a different job from checking what it does.**
Those are two separate modules on purpose. A suite can confirm that the rearward
CG limit holds the value the handbook prints and still never put a point behind
it, which would leave the tool's central function, refusing what should be
refused, untested. Every limit is therefore exercised at its boundary from both
sides: a point exactly on a limit has to be inside it, and a tenth past it has to
be outside. That pins down the value, the direction and the strictness of every
comparison built on it.

**A value that is missing is not a value that is wrong.** An input nobody filled
in produces a pending state, not an error and not a zero. The distinction has its
own tests because losing it is how a blank form starts reporting a pilot below
the minimum weight, or a takeoff weight computed with an undeclared tank.

**Relationships are swept systematically, not sampled at a few points.** Where a
property has to hold everywhere, such as the aircraft never landing heavier than
it took off, it is checked over a deterministic grid spanning the supported
ranges and their boundaries, rather than at a handful of chosen points. A grid
over continuous inputs is still a finite sample of them, and no number of grid
points proves a property over a continuum. What it buys is which points get
visited, stated in the code and the same on every run.

## Why these techniques

Three choices are worth stating, because each had a plausible alternative.

**The tests run in the browser, against the file that ships.** The calculator is
one self-contained HTML file with its dependencies vendored beside it and no
build step. A test runner under Node would need the logic pulled out into a
module, or a bundler standing in front of it, and either one puts a translation
step between what was tested and what is served. Loading the shipped file in a
browser removes that gap: the suite exercises the same code, the same vendored
Alpine and the same code path a user gets. The price is that running it needs a
browser, which `run_tests.sh` handles headlessly.

**Deterministic grid sweeps rather than property-based testing.** Property-based
testing was evaluated for the sweeps, with fast-check, and passed over for two
reasons.

The smaller one is packaging. Since its 2.x release fast-check publishes no
browser build; the documented options are importing it from a CDN, which would
break the offline guarantee this repository is built around, or bundling it
locally into a vendored file. Workable, and not the deciding factor.

The deciding one is the shape of the input space. This calculator takes a
handful of continuous parameters over known, bounded ranges, and what needs
checking in it is not a scattering of interior points but the edges: the ends of
a handbook table, where reading past the last row begins, and the boundary of
every limit. A grid can be laid down to land on those edges on purpose, and to
step through the interior at a known spacing on the way. Random generation
distributes its draws instead, spending most of them where the arithmetic is
unremarkable and reaching a narrow band at an edge only by chance and only with
enough draws. Neither approach exhausts a continuum. Over a space this small,
choosing the points deliberately is worth more than drawing more of them.

The coverage is also legible. A grid says in the code which points it visits and
what spacing it visits them at, and that statement does not change with a seed,
a generator or a library version. Property-based testing reproduces perfectly
when the seed is fixed, which it must be for this kind of use, but what a run
actually covered is not something a reader can see without running it.

That reasoning has a boundary, and it is worth naming. Property-based testing
would still be the better instrument for two things this suite does not do:
throwing arbitrary payloads at the session restore, which is covered here by
three handwritten ones, and generating random sequences of actions over the unit
switch, the reset and the aircraft selection. Bugs of that shape do not live in
a bounded numeric space and a grid will not find them.

**Mutation testing rather than coverage.** Coverage reports which lines ran. A
line can run in every single test and still have nothing asserted about it:
every constant in this calculator is executed by any worked example, so a
coverage report would show the whole file green while a wrong value sailed
through. Mutation testing asks the question coverage cannot, which is whether a
defect would be noticed.

## Measuring the suite: a mutation experiment

To answer that question, 39 deliberate defects were introduced into the
application code, one at a time, and the suite was run against each. All of it
ships with the repository: the defects in `verification/mutations.json`, the
harness in `verification/run_mutations.py`, the outcome in
`verification/results.json`.

The set is composed to cover the ways this kind of tool goes wrong: 23 edits to
constants, including transposed digits and figures that stay plausible; 7 to the
arithmetic and the logic; and 9 that widen a limit or delete a check outright.
That last group is written deliberately, because a calculator whose job is to
refuse fails dangerously in one direction only, and a defect that makes it
accept more than it should is worth more attention than one that makes it
accept less.

Each mutation is applied only to the application half of the file, never to the
tests, so that the module which writes the constants out a second time cannot be
edited along with the value it checks. Every layer is then run in isolation, so
a defect can be attributed to the module that catches it rather than to the
suite as a whole.

**All 39 are caught.** Attribution, counting only the mutations a given layer
catches when no other layer does:

| Layer | Mutations it catches on its own |
| --- | ---: |
| Envelope verdict | 8 |
| Load limits | 4 |
| POH source data | 3 |
| Worked examples | 2 |
| Invariants (grid sweeps) | 0 |

## What each layer turned out to be worth

**Writing the constants out against the handbook earns its place.** It is the
only thing that catches an edit to a value that is correct in form and wrong in
fact, which is the failure mode a handbook transcription is most exposed to.

**Exercising limits at their boundary does the heaviest lifting.** Twelve of the
39 are caught only by the two modules that do it, and every one of those twelve
is a defect that leaves the arithmetic intact and moves what the calculator
accepts. That is the failure this tool cannot afford, and nothing else in the
suite sees it.

**The grid sweeps caught nothing on their own.** The measured unique
contribution is zero, and there is no honest way to report that as anything
else. They are kept because what they assert is different in kind: a
relationship checked at every point of a grid rules out a whole class of wrong
answers rather than a list of specific ones, and the count above measures the
suite against 39 chosen mutations rather than against that class.

**Three mutations are caught only by the handbook comparison, for a reason worth
knowing.** The forward and rearward limits in the constants block never reach a
verdict: the getter that assembles the limits in force always overrides them
with the selected aircraft's. They are a documented reference, kept from
drifting away from the values actually in force by a cross-check that compares
all four. Editing them changes no behaviour, which is exactly why the only thing
that notices is the module comparing them to the handbook.

## Known deviations and open questions

**The envelope floor is not traceable.** The calculator uses 348.5 kg for every
registration. The chart labels that bound as the empty weight plus the minimum
solo pilot, which makes it a property of the aircraft rather than a constant,
and the nearest derivation from the handbook comes to 348.6. This is recorded in
the suite rather than asserted as correct.

**The forward limit is ambiguous in the source.** The handbooks define the
envelope as 25 % to 37 % MAC and print a conversion that puts 25 % at 265 mm.
The Trainer handbooks print 265; the PRO prints 267 while its own inches and its
own formula still say 265. The calculator uses 267 for both, because it is the
more restrictive reading, which is where a doubtful limit belongs.

**The handbook transcription was done by hand.** The constants are checked
against what a person read off the handbooks. That comparison catches drift
between the code and the transcription. It cannot catch an error made while
transcribing.

## Limits of what was measured

Mutation testing measures a suite against defects that somebody thought to
introduce. The 39 here were chosen to cover constants, arithmetic, boundaries
and the direction of each comparison. None of that says anything about a defect
nobody thought of. A count of zero escapes is a statement about this set of
mutations, not about the code.

The suite runs in headless Chromium only. It exercises the calculation and the
state machinery, not the rendering: the chart is stubbed out in the modules that
sweep, and no test looks at a pixel.

## Reproducing this

The suite:

```bash
./run_tests.sh
```

Or open `index.html?test=true` in a browser to watch it run, and use QUnit's
filter to isolate a module:

```
index.html?test=true&filter=Envelope verdict
index.html?test=true&filter=!POH source data
```

The mutation experiment:

```bash
python3 verification/run_mutations.py          # the whole set, around ten minutes
python3 verification/run_mutations.py M04 P01  # or just these
```

It needs nothing beyond Python 3 and the same browser the suite uses. The 39
defects live in `verification/mutations.json`, one entry each with the string it
replaces and what it replaces it with, and the recorded outcome is in
`verification/results.json`. Nothing on disk is modified while it runs: the
mutated page is held in memory and served from there, so an interrupted run
cannot leave a defect behind in `index.html`.

The recorded outcome carries the SHA-256 of the two files it was measured over,
and there is a check that takes milliseconds rather than ten minutes:

```bash
python3 verification/run_mutations.py --check
```

CI runs it on every push. A count measured over a file that has since changed is
not a weaker count, it is a statement about something that no longer exists, and
this is what keeps the number above from quietly becoming one. The whole of
`index.html` is hashed, tests included, because what each layer catches depends
on the tests as much as on the code. An edit that turns out to change nothing
still has to be measured for anyone to know that.

A count is only worth as much as the set it was measured over, which is why the
set ships too. Reading it is the fastest way to judge whether the 39 out of 39
above means anything, and adding to it is better still: a defect this set does
not cover is a defect nobody has checked for.
