import { describe, expect, it } from "vitest";
import { findFloatOffenders } from "../scripts/check-no-floats.ts";

describe("no fractional amounts", () => {
  it("keeps schema and code free of float literals and fractional SQL types", () => {
    expect(findFloatOffenders()).toEqual([]);
  });
});
