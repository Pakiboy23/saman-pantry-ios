import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  assertOutsideRepo,
  checkIngredients,
  describeFailure,
  type EvalCase,
  ingredientMatches,
  parseManifest,
  passed,
  repoRoot,
  SetupError,
} from "./recipe-eval.ts";

// Synthetic case only. Real manifests live outside the repo.
const okra: EvalCase = {
  id: "okra-with-onions",
  audio: "okra-with-onions.m4a",
  must_include: ["okra", "onion", "cumin", "salt", "red chili"],
  must_include_any: [["lemon juice", "vinegar"]],
  must_not_include: ["beans", "milk"],
};

Deno.test("spec manifest example parses", () => {
  const cases = parseManifest({ cases: [okra] });
  assertEquals(cases, [okra]);
});

Deno.test("manifest validation rejects bad shapes", () => {
  const bad: unknown[] = [
    null,
    {},
    { cases: [{ audio: "a.m4a", must_include: ["x"] }] },
    { cases: [{ id: "a", must_include: ["x"] }] },
    { cases: [{ id: "a", audio: "a.m4a", transcript: "a.txt", must_include: ["x"] }] },
    { cases: [{ id: "a", audio: "a.ogg", must_include: ["x"] }] },
    { cases: [{ id: "a", audio: "a.m4a" }] },
    { cases: [{ id: "a", audio: "a.m4a", must_include: [""] }] },
    { cases: [{ id: "a", audio: "a.m4a", must_include_any: [[]] }] },
    { cases: [{ id: "a", audio: "a.m4a", must_include: ["x"] }, { id: "a", transcript: "b.txt", must_include: ["x"] }] },
    { cases: [{ id: "../escape", audio: "a.m4a", must_include: ["x"] }] },
  ];
  for (const raw of bad) assertThrows(() => parseManifest(raw), SetupError);
});

Deno.test("transcript cases are allowed for old on-device regression inputs", () => {
  const [c] = parseManifest({ cases: [{ id: "old-1", transcript: "old-1.txt", must_not_include: ["beans"] }] });
  assertEquals(c.transcript, "old-1.txt");
  assertEquals(c.must_include, []);
});

Deno.test("ingredient matching handles plurals, spelling, and word boundaries", () => {
  assert(ingredientMatches("Onions", "onion"));
  assert(ingredientMatches("red onion", "onion"));
  assert(ingredientMatches("Kashmiri red chilli powder", "red chili"));
  assert(ingredientMatches("tomatoes", "tomato"));
  assert(ingredientMatches("garlic cloves", "garlic clove"));
  assertEquals(ingredientMatches("chili", "red chili"), false);
  assertEquals(ingredientMatches("chickpeas", "peas"), false);
  assertEquals(ingredientMatches("saltwater", "salt"), false);
});

Deno.test("checks report missing, any-of, and unexpected ingredients", () => {
  const good = checkIngredients(["okra", "onions", "cumin seeds", "salt", "red chili powder", "lemon juice"], okra);
  assert(passed(good));

  const bad = checkIngredients(["frozen beans", "onion", "salt", "milk"], okra);
  assertEquals(passed(bad), false);
  assertEquals(bad.missing, ["okra", "cumin", "red chili"]);
  assertEquals(bad.missingAny, [["lemon juice", "vinegar"]]);
  assertEquals(bad.unexpected, ["beans", "milk"]);
  assertEquals(
    describeFailure(bad),
    "missing: okra, cumin, red chili; none of: lemon juice | vinegar; unexpected: beans, milk",
  );
});

Deno.test("paths inside the repo are refused", () => {
  const root = repoRoot();
  assertThrows(() => assertOutsideRepo(`${root}/THESIS.md`, root, "Manifest"), SetupError, "inside the repo");
  assertThrows(() => assertOutsideRepo(root, root, "Manifest"), SetupError, "inside the repo");
  assertThrows(() => assertOutsideRepo(`${root}/does-not-exist.json`, root, "Manifest"), SetupError, "not found");
  const outside = Deno.makeTempFileSync({ suffix: ".json" });
  try {
    assertEquals(assertOutsideRepo(outside, root, "Manifest"), Deno.realPathSync(outside));
  } finally {
    Deno.removeSync(outside);
  }
});

Deno.test("a combined alternative satisfies must_include_any", () => {
  const result = checkIngredients(["okra", "onion", "cumin", "salt", "red chili", "lemon juice or vinegar"], okra);
  assert(passed(result));
});
