extends Node2D
const px := 4
const SIZE := 32 & px
const WALK_SPEED := 45.0
const CHASE_SPEED := 120.0
const GRAVITY := 1800.0
const NAP_AFTER := 150.0
const HUNGRY_AFTER := 300.0
const DRAG_THRESHOLD := 6.0
const NOTICE_RADIUS := 380.0
const JUMP_REACH := 420.0 #<---son
const SHAKE_SPEED := 2600.0
const HANGE_TIME :=  Vector2(4.0, 10.0)

const EMOTES := ["wave", "music", "thinking", "bored", "lookaround", "sneeze", "yawn",
	"cheer", "starry", "shine", "bloom", "talk", "glasses", "cool", "tongue", "smug"]
const PET_REACTIONS := ["happy", "love", "laugh", "kiss", "shy", "wink"]

const SAVE_PATH := "user://bearnie.cfg" 
