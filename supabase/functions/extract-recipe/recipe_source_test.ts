import { assert, assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import {
  assertResolvedPublic,
  captionsToText,
  classifyRecipeUrl,
  extractInstagramCaption,
  htmlToText,
  isPrivateAddress,
  MAX_INSTRUCTION_CHARS,
  MAX_RESPONSE_BYTES,
  MAX_SOURCE_CHARS,
  parseIngredientLine,
  parseYouTubeWatchPage,
  recipeFromJsonLd,
  resolveRecipeSource,
  SourceError,
  type FetchCtx,
} from "./recipe_source.ts";

const VIDEO = "dQw4w9WgXcQ";

function assertSafe(url: URL): Promise<void> {
  const host = url.hostname.toLowerCase();
  if (
    host === "127.0.0.1" || host === "localhost" || host === "[::1]" || host === "0.0.0.0" ||
    host.startsWith("10.") || host.startsWith("192.168.") || host.startsWith("169.254.")
  ) {
    throw new SourceError("blocked", "url_not_allowed", 400);
  }
  return Promise.resolve();
}

function ctx(fetchImpl: FetchCtx["fetchImpl"], extra: Partial<FetchCtx> = {}): FetchCtx {
  return { fetchImpl, assertSafe, ...extra };
}

Deno.test("classifies YouTube, Instagram, recipe sites, and blocked URLs", () => {
  const cases: Array<[string, string]> = [
    [`https://www.youtube.com/watch?v=${VIDEO}`, "youtube"],
    [`https://m.youtube.com/watch?v=${VIDEO}&t=12`, "youtube"],
    [`https://youtu.be/${VIDEO}`, "youtube"],
    [`youtu.be/${VIDEO}`, "youtube"],
    [`https://www.youtube.com/shorts/${VIDEO}`, "youtube"],
    [`https://www.youtube.com/embed/${VIDEO}`, "youtube"],
    ["https://www.instagram.com/reel/Abcdef/", "instagram"],
    ["https://instagram.com/p/Abcdef/", "instagram"],
    ["https://www.seriouseats.com/chicken-karahi", "web"],
    ["www.seriouseats.com/chicken-karahi", "web"],
    ["http://127.0.0.1/recipe", "blocked"],
    ["http://0177.0.0.1/recipe", "blocked"],
    ["http://2130706433/", "blocked"],
    ["http://10.1.2.3/admin", "blocked"],
    ["http://192.168.1.9/", "blocked"],
    ["http://169.254.169.254/latest/meta-data", "blocked"],
    ["http://[::1]/", "blocked"],
    ["http://[::ffff:127.0.0.1]/", "blocked"],
    ["http://localhost/recipe", "blocked"],
    ["http://printer/recipe", "blocked"],
    ["http://user:pass@example.com/recipe", "blocked"],
    ["file:///etc/passwd", "invalid"],
    ["javascript:alert(1)", "invalid"],
    ["not a link", "invalid"],
    ["haldi and pyaaz", "invalid"],
  ];
  for (const [raw, expected] of cases) {
    assertEquals(classifyRecipeUrl(raw), expected, raw);
  }
});

Deno.test("private address checks cover loopback, link-local, and mapped IPv6", () => {
  for (const ip of ["127.0.0.1", "10.0.0.5", "172.16.0.1", "172.31.255.1", "192.168.0.2", "169.254.169.254", "0.0.0.0", "100.64.0.1", "::1", "fc00::1", "fd00::1", "fe80::1", "::ffff:7f00:1", "[::1]"]) {
    assertEquals(isPrivateAddress(ip), true, ip);
  }
  for (const ip of ["8.8.8.8", "1.1.1.1", "172.15.0.1", "172.32.0.1", "2607:f8b0:4004:800::200e"]) {
    assertEquals(isPrivateAddress(ip), false, ip);
  }
});

Deno.test("DNS answers that point at a private address are refused", async () => {
  await assertRejects(
    () => assertResolvedPublic("evil.example", () => Promise.resolve(["8.8.8.8", "127.0.0.1"])),
    SourceError,
  );
  await assertResolvedPublic("ok.example", () => Promise.resolve(["8.8.8.8"]));
});

Deno.test("redirects to a private address are not followed", async () => {
  const calls: string[] = [];
  await assertRejects(
    () =>
      resolveRecipeSource("https://recipes.example/karahi", ctx((url) => {
        calls.push(url);
        return Promise.resolve(new Response(null, {
          status: 302,
          headers: { location: "http://169.254.169.254/latest/meta-data" },
        }));
      })),
    SourceError,
    "blocked",
  );
  assertEquals(calls, ["https://recipes.example/karahi"]);
});

Deno.test("oversized pages are rejected", async () => {
  const huge = "x".repeat(80);
  await assertRejects(
    () =>
      resolveRecipeSource("https://recipes.example/big", ctx(
        () => Promise.resolve(new Response(huge, { headers: { "content-type": "text/html", "content-length": String(huge.length) } })),
        { maxBytes: 40 },
      )),
    SourceError,
  );
});

const KARAHI_JSON_LD = `
<html><head>
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@graph": [
    { "@type": "WebSite", "name": "Not a recipe" },
    {
      "@type": ["Recipe", "BlogPosting"],
      "name": "Chicken Karahi",
      "author": { "@type": "Person", "name": "Mom" },
      "description": "Weeknight karahi.",
      "recipeIngredient": ["1 kg chicken", "haldi andaza se", "2 tbsp oil", "1½ tsp salt", "salt to taste"],
      "recipeInstructions": [
        {
          "@type": "HowToSection",
          "name": "Cook",
          "itemListElement": [
            { "@type": "HowToStep", "text": "Heat the oil." },
            { "@type": "HowToStep", "text": "Add the chicken &amp; haldi." }
          ]
        }
      ]
    }
  ]
}
</script>
</head><body><nav>Home</nav><p>Visible intro that is not the structured recipe.</p></body></html>`;

Deno.test("JSON-LD @graph Recipe is complete and skips the page text", () => {
  const recipe = recipeFromJsonLd(KARAHI_JSON_LD);
  if (!recipe) throw new Error("expected a recipe");
  assertEquals(recipe.title, "Chicken Karahi");
  assertEquals(recipe.attribution, "Mom");
  assertEquals(recipe.steps, ["Cook: Heat the oil.", "Cook: Add the chicken & haldi."]);
  assertEquals(recipe.notes, "Weeknight karahi.");
  assertEquals(recipe.ingredients[0], {
    ingredient: "chicken",
    original_phrase: "1 kg chicken",
    amount: 1,
    unit: "kg",
    vague: false,
  });
  assertEquals(recipe.ingredients[1].ingredient, "haldi");
  assertEquals(recipe.ingredients[1].amount, null);
  assertEquals(recipe.ingredients[1].vague, true);
  assertEquals(recipe.ingredients[1].original_phrase, "haldi andaza se");
  assertEquals(recipe.ingredients[2].amount, 2);
  assertEquals(recipe.ingredients[2].unit, "tbsp");
  assertEquals(recipe.ingredients[2].ingredient, "oil");
  assertEquals(recipe.ingredients[3].amount, 1.5);
  assertEquals(recipe.ingredients[3].unit, "tsp");
  assertEquals(recipe.ingredients[4].ingredient, "salt");
  assertEquals(recipe.ingredients[4].vague, true);
  assertEquals(recipe.ingredients[4].amount, null);
});

Deno.test("incomplete JSON-LD is not treated as a finished recipe", () => {
  const html = `<script type="application/ld+json">
    {"@type":"Recipe","name":"Chai","recipeIngredient":["2 cups doodh"]}
  </script>`;
  assertEquals(recipeFromJsonLd(html), null);
});

function instructionPage(instructions: unknown): string {
  return `<script type="application/ld+json">${JSON.stringify({
    "@type": "Recipe",
    name: "Rice",
    recipeIngredient: ["1 cup rice"],
    recipeInstructions: instructions,
  })}</script>`;
}

for (const [format, children] of [
  ["strings", Array(1000).fill("x")],
  ["objects", Array(1000).fill({ "@type": "HowToStep", text: "x" })],
  ["multiline strings", Array(1000).fill("x\nx")],
] as const) {
  Deno.test(`JSON-LD rejects heading amplification with ${format} before returning a recipe`, async () => {
    const html = instructionPage({
      "@type": "HowToSection",
      name: "H".repeat(1000),
      itemListElement: children,
    });
    assertEquals(new TextEncoder().encode(html).length < MAX_RESPONSE_BYTES, true);
    const error = await assertRejects(
      () => resolveRecipeSource("https://recipes.example/rice", ctx(() =>
        Promise.resolve(new Response(html, { headers: { "content-type": "text/html" } }))
      )),
      SourceError,
    );
    assertEquals(error.code, "url_fetch_failed");
    assertEquals(error.status, 422);
  });
}

Deno.test("instruction budget includes prefixes and is shared by nested and sibling sections", () => {
  const line = "x".repeat(MAX_INSTRUCTION_CHARS / 2 - "Cook: ".length);
  const instructions = [
    { "@type": "HowToSection", name: "Cook", itemListElement: [line] },
    {
      "@type": "HowToSection",
      name: "Outer",
      recipeInstructions: {
        "@type": "HowToSection",
        name: "Cook",
        itemListElement: [{ "@type": "HowToStep", text: line }],
      },
    },
  ];
  const recipe = recipeFromJsonLd(instructionPage(instructions));
  if (!recipe) throw new Error("expected a recipe at the limit");
  assertEquals(recipe.steps, [`Cook: ${line}`, `Cook: ${line}`]);
  // Exercise the existing HTTP response shape, including the required raw copy.
  const response = JSON.parse(JSON.stringify({ recipe, raw_json: JSON.stringify(recipe) }));
  assertEquals(JSON.parse(response.raw_json), response.recipe);
  assertThrows(
    () => recipeFromJsonLd(instructionPage([...instructions, "x"])),
    SourceError,
  );
});

Deno.test("instruction budget rejects a single oversized heading or unsectioned step", () => {
  for (const instructions of [
    { "@type": "HowToSection", name: "H".repeat(MAX_INSTRUCTION_CHARS), itemListElement: ["x"] },
    "x".repeat(MAX_INSTRUCTION_CHARS + 1),
    { "@type": "HowToStep", text: "x".repeat(MAX_INSTRUCTION_CHARS + 1) },
  ]) {
    assertThrows(() => recipeFromJsonLd(instructionPage(instructions)), SourceError);
  }
});

Deno.test("nonempty instructions cannot bypass the budget with many tiny steps", () => {
  const steps = Array(MAX_INSTRUCTION_CHARS).fill("x");
  assertEquals(recipeFromJsonLd(instructionPage(steps))?.steps.length, MAX_INSTRUCTION_CHARS);
  assertThrows(() => recipeFromJsonLd(instructionPage([...steps, "x"])), SourceError);
});

Deno.test("a complete JSON-LD page does not need the model text", async () => {
  const resolved = await resolveRecipeSource("https://recipes.example/karahi", ctx(() =>
    Promise.resolve(new Response(KARAHI_JSON_LD, { headers: { "content-type": "text/html" } }))
  ));
  assertEquals(resolved.kind, "recipe");
  if (resolved.kind === "recipe") assertEquals(resolved.recipe.title, "Chicken Karahi");
});

Deno.test("a page without JSON-LD sends cleaned text and drops scripts", async () => {
  const html = `<html><body><script>secretToken = "do-not-send"</script><nav>Menu</nav>
    <h1>Aloo gosht</h1><p>Ingredients: 1 kg mutton, 2 tsp haldi. Fry the onion, then simmer.</p></body></html>`;
  assertEquals(htmlToText(html).includes("secretToken"), false);
  assertEquals(htmlToText(html).includes("Menu"), false);
  const resolved = await resolveRecipeSource("https://recipes.example/aloo", ctx(() =>
    Promise.resolve(new Response(html, { headers: { "content-type": "text/html" } }))
  ));
  assertEquals(resolved.kind, "text");
  if (resolved.kind === "text") {
    assertEquals(resolved.text.includes("secretToken"), false);
    assertEquals(resolved.text.includes("mutton"), true);
    assertEquals(resolved.source, "web");
  }
});

Deno.test("ingredient lines keep real quantities and refuse invented ones", () => {
  const half = parseIngredientLine("1/2 cup dahi");
  assertEquals(half.amount, 0.5);
  assertEquals(half.unit, "cup");
  assertEquals(half.ingredient, "dahi");
  assertEquals(half.vague, false);

  const range = parseIngredientLine("2-3 tbsp oil");
  assertEquals(range.amount, 2);
  assertEquals(range.unit, "tbsp");
  assertEquals(range.ingredient, "oil");
  assertEquals(range.vague, true);

  const handful = parseIngredientLine("a handful of cilantro");
  assertEquals(handful.amount, null);
  assertEquals(handful.unit, null);
  assertEquals(handful.ingredient, "cilantro");
  assertEquals(handful.vague, true);
  assertEquals(handful.original_phrase, "a handful of cilantro");
});

const WATCH_HTML = `
<html><script>var ytInitialPlayerResponse = {"videoDetails":{"title":"Aloo Gosht","author":"Ammi","shortDescription":"Subscribe for more videos!!"},"captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[
  {"baseUrl":"https://www.youtube.com/api/timedtext?v=${VIDEO}&lang=hi","languageCode":"hi"},
  {"baseUrl":"https://www.youtube.com/api/timedtext?v=${VIDEO}&lang=en","languageCode":"en"},
  {"baseUrl":"http://169.254.169.254/latest","languageCode":"en","kind":"asr"}
]}}};</script></html>`;

Deno.test("YouTube watch page prefers a manual English caption track", () => {
  const parsed = parseYouTubeWatchPage(WATCH_HTML);
  assertEquals(parsed.title, "Aloo Gosht");
  assertEquals(parsed.channel, "Ammi");
  assertEquals(parsed.captionUrl, `https://www.youtube.com/api/timedtext?v=${VIDEO}&lang=en`);
});

Deno.test("caption XML decodes entities", () => {
  const text = captionsToText(`<transcript><text>Heat oil &amp; add 1 kg mutton.</text><text>Simmer.</text></transcript>`);
  assertEquals(text, "Heat oil & add 1 kg mutton. Simmer.");
});

Deno.test("YouTube Data API description that is already a recipe skips the watch page", async () => {
  const calls: string[] = [];
  const resolved = await resolveRecipeSource(`https://youtu.be/${VIDEO}`, ctx((url) => {
    calls.push(url);
    if (!url.includes("googleapis.com/youtube/v3/videos")) {
      return Promise.reject(new Error(`unexpected fetch ${url}`));
    }
    assertEquals(url.includes(`id=${VIDEO}`), true);
    assertEquals(url.includes("key=test-key"), true);
    return Promise.resolve(Response.json({
      items: [{
        snippet: {
          title: "Chicken Karahi",
          channelTitle: "Ammi",
          description: "Ingredients: 1 kg chicken, 2 tbsp oil, 1 tsp haldi. Fry, then simmer until the oil separates.",
        },
      }],
    }));
  }, { youtubeApiKey: "test-key" }));
  assertEquals(calls.length, 1);
  assertEquals(resolved.kind, "text");
  if (resolved.kind === "text") {
    assertEquals(resolved.source, "youtube");
    assertEquals(resolved.text.includes("Chicken Karahi"), true);
    assertEquals(resolved.text.includes("haldi"), true);
    assertEquals(resolved.text.includes("Channel: Ammi"), true);
  }
});

Deno.test("a thin YouTube description falls back to captions and ignores non-YouTube caption URLs", async () => {
  const calls: string[] = [];
  const resolved = await resolveRecipeSource(`https://www.youtube.com/shorts/${VIDEO}`, ctx((url) => {
    calls.push(url);
    if (url.includes("169.254.169.254")) return Promise.reject(new Error("metadata fetch"));
    if (url.includes("googleapis.com")) {
      return Promise.resolve(Response.json({
        items: [{ snippet: { title: "Aloo Gosht", description: "Subscribe for more videos!!", channelTitle: "Ammi" } }],
      }));
    }
    if (url.includes("/watch?")) {
      return Promise.resolve(new Response(WATCH_HTML, { headers: { "content-type": "text/html" } }));
    }
    if (url.includes("timedtext") && url.includes("lang=en")) {
      return Promise.resolve(new Response(
        `<transcript><text>Heat the oil. Add 1 kg mutton and haldi. Cook until tender.</text></transcript>`,
        { headers: { "content-type": "text/xml" } },
      ));
    }
    return Promise.resolve(new Response("no", { status: 404 }));
  }, { youtubeApiKey: "test-key" }));
  assertEquals(calls.some((url) => url.includes("169.254.169.254")), false);
  assertEquals(calls.some((url) => url.includes("timedtext") && url.includes("lang=en")), true);
  if (resolved.kind !== "text") throw new Error("expected text");
  assertEquals(resolved.text.includes("mutton"), true);
  assertEquals(resolved.text.includes("Aloo Gosht"), true);
});

Deno.test("without an API key, the watch page is the YouTube fallback", async () => {
  const calls: string[] = [];
  const html = WATCH_HTML.replace(
    "Subscribe for more videos!!",
    "Ingredients: 2 cups atta and 1 tsp salt. Knead, roll, and cook on a tawa.",
  );
  const resolved = await resolveRecipeSource(`https://www.youtube.com/watch?v=${VIDEO}`, ctx((url) => {
    calls.push(url);
    assertEquals(url.includes("googleapis.com"), false);
    return Promise.resolve(new Response(html, { headers: { "content-type": "text/html" } }));
  }));
  assertEquals(calls.length, 1);
  if (resolved.kind !== "text") throw new Error("expected text");
  assertEquals(resolved.text.includes("atta"), true);
  assertEquals(resolved.text.includes("Transcript:"), false);
});

Deno.test("Instagram returns the caption when the page exposes it", async () => {
  const resolved = await resolveRecipeSource("https://www.instagram.com/reel/Abcdef/", ctx(() =>
    Promise.resolve(new Response(
      `<meta property="og:description" content="Ammi&apos;s chicken karahi: 1 kg chicken, haldi andaza se, fry then simmer.">`,
      { headers: { "content-type": "text/html" } },
    ))
  ));
  if (resolved.kind !== "text") throw new Error("expected text");
  assertEquals(resolved.source, "instagram");
  assertEquals(resolved.text.includes("chicken karahi"), true);
});

Deno.test("Instagram login walls ask for the caption instead of calling the model", async () => {
  const html = `<html><title>Login • Instagram</title><meta property="og:description" content="Create an account or log in to Instagram"></html>`;
  assertEquals(extractInstagramCaption(html), null);
  const error = await assertRejects(
    () => resolveRecipeSource("https://www.instagram.com/p/Abcdef/", ctx(() =>
      Promise.resolve(new Response(html, { headers: { "content-type": "text/html" } }))
    )),
    SourceError,
  );
  assertEquals((error as SourceError).code, "instagram_caption_unavailable");
});

Deno.test("a private URL never calls fetch", async () => {
  let called = false;
  const error = await assertRejects(
    () => resolveRecipeSource("http://127.0.0.1/recipe", ctx(() => {
      called = true;
      return Promise.resolve(new Response("no"));
    })),
    SourceError,
  );
  assertEquals(called, false);
  assertEquals((error as SourceError).code, "url_not_allowed");
});

Deno.test("parseModelRecipe tolerates fences, prose, and flags empty recipes", async () => {
  const { parseModelRecipe, classifyModelRecipe } = await import("./recipe_source.ts");
  const good = '{"title":"Dal","attribution":null,"ingredients":[{"ingredient":"lentils","original_phrase":"1 cup masoor","amount":1,"unit":"cup","vague":false}],"steps":["Boil {gently}"],"notes":null}';
  const fenced = parseModelRecipe("```json\n" + good + "\n```");
  assertEquals(typeof fenced === "object" && fenced?.title, "Dal");
  const prose = parseModelRecipe("Here is the recipe you asked for:\n\n" + good + "\n\nEnjoy!");
  assertEquals(typeof prose === "object" && prose?.ingredients.length, 1);
  assertEquals(parseModelRecipe('{"error":"no_recipe"}'), "no_recipe");
  assertEquals(parseModelRecipe('{"title":null,"attribution":"X","ingredients":[],"steps":[],"notes":null}'), "no_recipe");
  assertEquals(parseModelRecipe("I could not find a recipe on this page."), null);
  assertEquals(parseModelRecipe('{"title":"Cut off","ingredients":[{"ingredient":"salt"'), null);
  assertEquals(classifyModelRecipe('{"error":"no_recipe"}'), {
    outcome: "no_recipe",
    reason: "explicit_no_recipe",
  });
  assertEquals(classifyModelRecipe('{"title":"","ingredients":[{"ingredient":"salt"}]}'), {
    outcome: "no_recipe",
    reason: "missing_title",
  });
  assertEquals(classifyModelRecipe('{"title":"Dal","ingredients":[]}'), {
    outcome: "no_recipe",
    reason: "empty_ingredients",
  });
  assertEquals(classifyModelRecipe('{"title":null,"ingredients":[]}'), {
    outcome: "no_recipe",
    reason: "missing_title_and_ingredients",
  });
});

Deno.test("HTML tag removal preserves text, formatting, and malformed brackets", () => {
  const cases = [
    ["", ""],
    ["Plain text &amp; salt", "Plain text & salt"],
    ["<p>Heat<br>oil</p><p>Add <b>salt</b>.</p>", "Heat\noil\n Add salt ."],
    ["<", "<"],
    ["<>", "<>"],
    ["before <<x>after", "before after"],
    ["before <>after <x <y", "before <>after <x <y"],
    ["&lt;b&gt;salt&lt;/b&gt;", "<b>salt</b>"],
  ];
  for (const [html, expected] of cases) {
    assertEquals(htmlToText(html), expected, html);
  }
});

Deno.test("unfinished tags reach the web fallback and output cap without excessive CPU work", async () => {
  const html = "Ingredients: salt. Simmer. " + "<x ".repeat(40_000);
  const start = performance.now();
  const resolved = await resolveRecipeSource("https://recipes.example/malformed", ctx(() =>
    Promise.resolve(new Response(html, { headers: { "content-type": "text/html" } }))
  ));
  const elapsed = performance.now() - start;
  assertEquals(resolved.kind, "text");
  if (resolved.kind !== "text") throw new Error("expected text");
  assertEquals(resolved.text, (`URL: https://recipes.example/malformed\n\n${html}`).slice(0, MAX_SOURCE_CHARS));
  // A generous ceiling for a 120 KB page; the old suffix rescans take seconds.
  assert(elapsed < 1000, `Malformed HTML took ${elapsed} ms`);
});

Deno.test("unfinished tags in structured instructions and captions remain text", () => {
  const text = "Simmer. " + "<x ".repeat(40_000);
  const start = performance.now();
  assertThrows(() => recipeFromJsonLd(`<script type="application/ld+json">${JSON.stringify({
    "@type": "Recipe",
    name: "Dal",
    recipeIngredient: ["1 cup lentils"],
    recipeInstructions: text,
  })}</script>`), SourceError, "That recipe is too large");
  assertEquals(captionsToText(`<transcript><text>${text}</text></transcript>`), text.trim());
  assert(performance.now() - start < 1000, "Malformed recipe text took excessive CPU time");
});


Deno.test("JSON-LD scanning preserves case, quotes, attributes, and entity decoding", () => {
  const html = KARAHI_JSON_LD
    .replace('<script type="application/ld+json">', "<ScRiPt id='recipe' TYPE = 'APPLICATION/LD+JSON' defer>")
    .replace("</script>", "</ScRiPt>")
    .replaceAll('"', "&quot;");
  assertEquals(recipeFromJsonLd(html), recipeFromJsonLd(KARAHI_JSON_LD));
});

Deno.test("JSON-LD scanning skips unrelated, invalid, and incomplete blocks", () => {
  const prefix = `<script type="text/javascript">{"@type":"Recipe"}</script>
    <script type="application/ld+json">not JSON</script>
    <script type="application/ld+json">{"@type":"Recipe","name":"Incomplete"}</script>`;
  assertEquals(recipeFromJsonLd(prefix + KARAHI_JSON_LD), recipeFromJsonLd(KARAHI_JSON_LD));
  assertEquals(recipeFromJsonLd(KARAHI_JSON_LD.split("</script>")[0]), null);
});

Deno.test("script-looking text inside a script is not another JSON-LD block", () => {
  assertEquals(recipeFromJsonLd("<script>" + KARAHI_JSON_LD + "</script>"), null);
});

Deno.test("malformed script pages stay within a bounded parsing budget", async () => {
  const fragments = [
    "<script ",
    '<script type="application/ld+json">',
    '<SCRIPT type="application/ld+json"></scriptx>',
  ];
  for (const fragment of fragments) {
    const html = fragment.repeat(Math.floor(MAX_RESPONSE_BYTES / fragment.length));
    const started = performance.now();
    assertEquals(recipeFromJsonLd(html), null);
    assertEquals(htmlToText(html), "");
    // A generous absolute ceiling avoids noisy timing ratios while detecting
    // overlapping suffix scans on a page within the production download cap.
    assertEquals(performance.now() - started < 1000, true, fragment);
    const error = await assertRejects(
      () => resolveRecipeSource("https://recipes.example/malformed", ctx(() =>
        Promise.resolve(new Response(html, { headers: { "content-type": "text/html" } }))
      )),
      SourceError,
    );
    assertEquals((error as SourceError).code, "no_recipe_text");
  }
});

Deno.test("text fallback keeps visible content before an unfinished script", async () => {
  const visible = "Ingredients: 1 kg mutton, 2 tsp haldi. Fry the onion, then simmer.";
  for (const tail of ["<script ".repeat(1000), '<script type="application/ld+json">private script text']) {
    const html = `<p>${visible}</p>${tail}`;
    assertEquals(htmlToText(html), visible);
    const resolved = await resolveRecipeSource("https://recipes.example/aloo", ctx(() =>
      Promise.resolve(new Response(html, { headers: { "content-type": "text/html" } }))
    ));
    if (resolved.kind !== "text") throw new Error("expected text");
    assertEquals(resolved.text, `URL: https://recipes.example/aloo\n\n${visible}`);
  }
});


Deno.test("HTML whitespace normalization preserves line breaks and single tabs", () => {
  const cases = [
    ["  a\t b \t\n\n \t\n c  ", "a b\n\n c"],
    ["a\tb\tc", "a\tb\tc"],
    ["a\t\nb \n c", "a\nb\n c"],
    ["a \t\r\nb", "a \r\nb"],
    ["<p>Ingredients:  1 cup rice&nbsp;&#9;</p><p>Boil<br>Serve</p>", "Ingredients: 1 cup rice\n Boil\nServe"],
  ];
  for (const [html, expected] of cases) {
    assertEquals(htmlToText(html), expected);
  }
});

Deno.test("HTML normalization handles long whitespace runs without a newline", () => {
  for (const whitespace of [" ", "\t", " \t"]) {
    const run = whitespace.repeat(100_000);
    assertEquals(htmlToText(`a${run}b`), "a b");
    assertEquals(htmlToText(`a${run}\nb`), "a\nb");
    assertEquals(htmlToText(`a${run}`), "a");
  }
});

Deno.test("a whitespace-only HTML response at the byte cap returns no recipe", async () => {
  const error = await assertRejects(
    () => resolveRecipeSource("https://recipes.example/blank", ctx(() =>
      Promise.resolve(new Response(" ".repeat(MAX_RESPONSE_BYTES), {
        headers: { "content-type": "text/html" },
      }))
    )),
    SourceError,
  );
  assertEquals(error.code, "no_recipe_text");
  assertEquals(error.status, 422);
});


Deno.test("HTML cleanup preserves text around mixed-case blocks and adjacent blocks", () => {
  for (const tag of ["script", "style", "noscript", "svg", "nav", "footer", "header"]) {
    const html = `İ before<${tag.toUpperCase()} data-value="x">hidden</${tag.toUpperCase()}>` +
      `<${tag}>also hidden</${tag}>after`;
    assertEquals(htmlToText(html), "İ before after", tag);
  }
  assertEquals(htmlToText("before<!-- hidden --><!-- hidden too -->after"), "before after");
  assertEquals(htmlToText("<scripture>visible</scripture>"), "visible");
  assertEquals(htmlToText("<p>one &amp; two</p><p>three<br>four</p>"), "one & two\n three\nfour");
});

Deno.test("HTML cleanup discards unterminated blocks including repeated incomplete openers", () => {
  for (const tag of ["script", "style", "noscript", "svg", "nav", "footer", "header"]) {
    for (const opener of [`<${tag}>`, `<${tag} `]) {
      assertEquals(htmlToText(`visible${opener.repeat(1000)}hidden`), "visible", opener);
    }
  }
  assertEquals(htmlToText(`visible${"<!--".repeat(1000)}hidden`), "visible");
});

Deno.test("JSON-LD scanning skips invalid scripts and resumes after each closed block", () => {
  const html = `<script>const nested = '<script type="application/ld+json">';</script>` +
    `<script type="application/ld+json">invalid JSON</script>` +
    KARAHI_JSON_LD.replaceAll("script", "SCRIPT");
  assertEquals(recipeFromJsonLd(html)?.title, "Chicken Karahi");
  const unclosed = KARAHI_JSON_LD.slice(0, KARAHI_JSON_LD.indexOf("</script>"));
  assertEquals(recipeFromJsonLd(unclosed), null);
});

Deno.test("response-cap pages with unclosed scripts resolve without exposing script text", async () => {
  const prefix = "<p>Ingredients: 1 cup lentils. Boil in water, then simmer until tender.</p>";
  for (const opener of ["<script>", '<script type="application/ld+json">', "<script "]) {
    const html = prefix + opener.repeat(Math.floor((MAX_RESPONSE_BYTES - prefix.length) / opener.length));
    const resolved = await resolveRecipeSource("https://recipes.example/malformed", ctx(() =>
      Promise.resolve(new Response(html, { headers: { "content-type": "text/html" } }))
    ));
    assertEquals(resolved.kind, "text");
    if (resolved.kind === "text") {
      assertEquals(resolved.text, "URL: https://recipes.example/malformed\n\nIngredients: 1 cup lentils. Boil in water, then simmer until tender.");
    }
  }
});

Deno.test("a page containing only an unclosed script reports no recipe", async () => {
  const error = await assertRejects(
    () => resolveRecipeSource("https://recipes.example/empty", ctx(() =>
      Promise.resolve(new Response('<script type="application/ld+json">' + "<script>".repeat(1000)))
    )),
    SourceError,
  );
  assertEquals((error as SourceError).code, "no_recipe_text");
});
