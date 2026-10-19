// The database side of note_assist (note_assist.ts decides everything; this
// file only reads). The note is read with the CALLER's client, so row level
// security decides what exists for them: a note in a conversation they are
// not in, or in a suspended circle, is simply not found.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type {
  LoadedNote,
  NoteAssistStore,
  NoteSourceBlock,
} from "./note_assist.ts";

// deno-lint-ignore no-explicit-any
type Client = SupabaseClient<any, any, any>;

const CELL_CHARS = 300;

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}

/// The rows of a table block's props as rows of cell text, in column order.
export function tableRows(props: unknown): string[][] {
  if (props === null || typeof props !== "object") return [];
  const p = props as Record<string, unknown>;
  const cols = Array.isArray(p.cols)
    ? p.cols.filter((col): col is string => typeof col === "string")
    : [];
  if (!Array.isArray(p.rows)) return [];
  const rows: string[][] = [];
  for (const row of p.rows.slice(0, 200)) {
    if (row === null || typeof row !== "object") continue;
    const cells = (row as Record<string, unknown>).c;
    const map = cells !== null && typeof cells === "object"
      ? cells as Record<string, unknown>
      : {};
    rows.push(cols.map((col) => text(map[col]).slice(0, CELL_CHARS)));
  }
  return rows;
}

/// A stored block as the prompt builder reads it.
export function blockFromRow(row: Record<string, unknown>): NoteSourceBlock {
  const kind = text(row.kind) || "paragraph";
  const props = row.props !== null && typeof row.props === "object"
    ? row.props as Record<string, unknown>
    : {};
  return {
    kind,
    text: text(row.text),
    checked: props.checked === true,
    rows: kind === "table" ? tableRows(props) : undefined,
  };
}

export function createNoteAssistStore(userClient: Client): NoteAssistStore {
  return {
    aiEnabled: async (userId) => {
      const { data } = await userClient
        .from("user_ai_settings")
        .select("ai_enabled")
        .eq("user_id", userId)
        .maybeSingle();
      const value = (data as { ai_enabled?: boolean | null } | null)
        ?.ai_enabled;
      return typeof value === "boolean" ? value : null;
    },
    loadNote: async (_userId, noteId): Promise<LoadedNote | null> => {
      const { data: note, error } = await userClient
        .from("notes")
        .select("id,conversation_id,title,deleted_at")
        .eq("id", noteId)
        .maybeSingle();
      if (error) {
        throw new Error(`notes: ${error.message}`);
      }
      const row = note as Record<string, unknown> | null;
      if (
        !row || row.deleted_at !== null ||
        typeof row.conversation_id !== "string"
      ) {
        return null;
      }
      const { data: blocks, error: blocksError } = await userClient
        .from("note_blocks")
        .select("kind,text,props,pos,id")
        .eq("note_id", noteId)
        .eq("deleted", false)
        .order("pos", { ascending: true })
        .order("id", { ascending: true })
        .limit(2000);
      if (blocksError) {
        throw new Error(`note_blocks: ${blocksError.message}`);
      }
      return {
        conversationId: row.conversation_id,
        title: text(row.title),
        blocks: (blocks ?? []).map((block) =>
          blockFromRow(block as Record<string, unknown>)
        ),
      };
    },
  };
}
