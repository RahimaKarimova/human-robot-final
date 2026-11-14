class_name CompanionNotices
extends RefCounted
## Fixed development UI notices, never generated robot speech.
const TEXTS := {
	"UNRECOGNIZED": "Control not recognized. Use the on-screen buttons or try a listed command.",
	"UNAVAILABLE": "Request service is unavailable. Use the on-screen controls.",
	"STALE_REQUEST": "The game moved to another step. Please try the request again.",
	"WAITING": "Take your time. This request does not advance the conversation.",
	"REPEAT_OR_SKIP": "You can repeat the same question or skip it; no extra detail is required.",
	"DEVELOPMENT_PRIVACY": "Development mode: no audio or reply transcripts are saved. The microphone's listening status is shown above. You can skip any question.",
	"HINT_UNAVAILABLE": "Ask for a hint while a puzzle is open. Finish or skip this checkpoint first.",
	"NO_QUESTION": "There is no active question for that request.",
	"ALREADY_STOPPED": "This session has ended."
}
