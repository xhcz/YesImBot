import { AsyncLocalStorage } from "node:async_hooks";

type LogTarget = {
    platform?: string;
    selfId?: string;
    channelId?: string;
    guildId?: string;
    isDirect?: boolean;
    messageId?: string;
};

const scope = new AsyncLocalStorage<string | undefined>();

function logValue(value: string): string {
    return value.replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}\[\]]/gu, "_").slice(0, 512);
}

export function formatLogTarget(target: LogTarget): string {
    const kind = target.isDirect || target.channelId?.startsWith("private:") ? "私聊" : "群聊";
    const channel = logValue(target.channelId ?? "未知");
    const guild = target.guildId && target.guildId !== target.channelId ? `（群 ${logValue(target.guildId)}）` : "";
    return `[${logValue(target.platform ?? "未知")}/${logValue(target.selfId ?? "未知")}/${kind} ${channel}${guild}]`;
}

// Keep the full identifier in decision records and error reports.
function displayTurnId(id: string): string {
    const decision = /^([0-9a-f]{8})-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-\d+-(\d+)$/i.exec(id);
    return decision ? `${decision[1]}/${decision[2]}` : logValue(id);
}

export function withConversationLog<T>(target: LogTarget | undefined, turnId: string | undefined, run: () => T): T {
    if (!target?.channelId) return scope.run(undefined, run);
    const message = target.messageId ? ` [消息 ${logValue(target.messageId)}]` : "";
    const turn = turnId ? ` [轮次 ${displayTurnId(turnId)}]` : "";
    return scope.run(`${formatLogTarget(target)}${message}${turn}`, run);
}

export function conversationLogPrefix(): string | undefined {
    return scope.getStore();
}
