@tool
class_name McpStartupPath
extends RefCounted

## Retired v4 lifecycle vocabulary kept only because this class_name and its
## constants were published. Runtime startup state lives in one tagged episode.
const UNSET := ""
const GUARDED := "guarded"
const ADOPTED := "adopted"
const SPAWNED := "spawned"
const CRASHED := "crashed"
const RESERVED := "reserved"
const NO_COMMAND := "no_command"
const INCOMPATIBLE := "incompatible"
const FREE := "free"
