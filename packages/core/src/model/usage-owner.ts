import type { Context } from "koishi";

import type { LoggerService } from "../logger";

/** Per-model-service identity; its context supplies persistence and disposal. */
export interface UsageOwner {
    context: Context;
    logging?: Pick<LoggerService, "getLogger">;
}

export function resolveUsageOwner(ctx: Context, explicitOwner?: UsageOwner): UsageOwner | undefined {
    // Model-service internals cannot inject their own service. Commands may resolve
    // it through their declared dependency; transports receive the owner directly.
    return explicitOwner ?? ctx.yesimbot?.model?.usageOwner;
}
