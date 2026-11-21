import { describe, expect, it } from "vitest";

import { keywordScore, recallTokens } from "../src/continuity";

describe("mixed-script recall", () => {
    it("matches separated terms and ranks the original wording higher", () => {
        const tokens = recallTokens("Koishi配置");
        const separated = keywordScore("Koishi 的配置", tokens);
        expect(separated).toBeGreaterThan(0);
        expect(keywordScore("Koishi配置", tokens)).toBeGreaterThan(separated);
    });

    it("keeps explicit terms ahead of generated fragments within the budget", () => {
        const tokens = recallTokens("一二三四五六七八九十甲乙丙丁戊己庚辛壬癸天地玄黄宇宙 SQLite");
        expect(tokens).toContain("sqlite");
        expect(tokens).toHaveLength(24);
    });

    it("does not expand mixed terms into single-character candidates", () => {
        expect(recallTokens("用Koishi")).toEqual(["用koishi", "koishi"]);
        expect(recallTokens("用")).toEqual(["用"]);
    });
});
