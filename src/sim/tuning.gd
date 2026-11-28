extends RefCounted
## All gameplay feel numbers. Units: yards, seconds.

# Movement
const RUN_SPEED := 7.0
const SPRINT_SPEED := 9.5
const DECEL := 24.0          # slide deceleration after a tackle dive
const BLOCK_SPEED := 2.8
const DASH_SPEED := 13.0
const SPIN_SPEED := 7.5
const DASH_TIME := 0.22
const SPIN_TIME := 0.32
const MOVE_CHARGE_PER_YARD := 0.05
# Jump (#379): Space / A in live play. A committed hop: takeoff velocity, no steering.
const JUMP_TIME := 0.6             # s in the air
const JUMP_HEIGHT := 0.9           # yd, feet at the peak (mid-air)
const JUMP_STAMINA := 0.05         # stamina per jump
const JUMP_CHAIN_STAMINA := 0.25   # instead, for a jump within JUMP_CHAIN_WINDOW of the last landing
const JUMP_CHAIN_WINDOW := 0.5     # s after landing
const QB_DROPBACK_SLOW_START := 14.0  # yards behind the line of scrimmage
const QB_DROPBACK_SLOW_END := 20.0
const QB_DROPBACK_SPEED_FLOOR := 0.65

# Stamina (0..1)
const STAMINA_DRAIN := 0.25  # per second while sprinting
const STAMINA_REGEN := 0.15  # per second while not sprinting
const STAMINA_LOCKOUT_RECOVER := 0.25

# Field (regulation)
const FIELD_LENGTH := 100.0
const FIELD_WIDTH := 53.33
const ENDZONE_DEPTH := 10.0
const OOB_MARGIN := 2.0

# Ball
const SNAP_TIME := 0.35        # seconds for snap flight C -> QB
const BALL_CARRY_HEIGHT := 1.1 # yards above turf when held

# Run game
const HANDOFF_REACH := 1.6
const HANDOFF_COOLDOWN := 0.8
const AI_HANDOFF_WINDOW := 1.5
const RUN_BLOCK_LANE_WEIGHT := 0.55

# Passing
const GRAVITY := 10.73          # yd/s^2
const RELEASE_HEIGHT := 2.0
const CATCH_HEIGHT := 1.1
const THROW_SPEED_MIN := 12.0
const THROW_SPEED_MAX := 30.0
const THROW_INHERIT := 0.3      # fraction of thrower velocity added to ball
const PLAYER_PASS_POWER := 0.68
const THROW_CHARGE_TIME := 0.9  # POV passer: seconds of hold to full power (distance)

# Offensive alignment, as fractions of the field width.
const TWINS_RIGHT_INNER_X := 0.68
const TWINS_RIGHT_OUTER_X := 0.84

# Catching
const CATCH_RADIUS := 1.2
const CATCH_MIN_HEIGHT := 0.3
const CATCH_MAX_HEIGHT := 2.6
const CONTEST_MARGIN := 0.35
const MIN_PASS_TRAVEL := 2.5      # ball must travel this far before it can be caught/deflected
const BATTED_PASS_MAX_TRAVEL := 5.0   # short defensive contact ends the pass incomplete
const INT_RADIUS := 0.6           # defender must be this close to the ball to intercept
const GROUNDING_PRESSURE_RADIUS := 2.5
const GROUNDING_RECEIVER_RADIUS := 5.0

# Tackling
const DIVE_SPEED := 11.0
const DIVE_TIME := 0.35
const TACKLE_REACH := 1.0
const DIVE_RECOVER := 1.0
# Forward progress (C06a, #98): a tackle is spotted where the carrier's progress was stopped
const CONTACT_REACH := 1.0            # an opponent this close is "in contact" with the carrier
const FORWARD_PROGRESS_GRACE := 0.3   # s the contact window stays open after contact breaks
const FORWARD_PROGRESS_BANNER := 0.5  # yd credited back before the HUD calls it out

# Q / E spin: the evade spin (SPIN_TIME/SPIN_SPEED above) angled this far off facing
const SPIN_ANGLE := 35.0        # degrees

# POV passing: the QB's view pitch sets the launch angle
const POV_ANGLE_MIN := -10.0    # degrees
const POV_ANGLE_MAX := 70.0

# Placeholder AI
const AI_RUSH_DELAY := 2.5
const AI_DIVE_RANGE := 2.0

# Bodies + blocking
const BODY_RADIUS := 0.45
const ENGAGE_DIST := 1.0
const ENGAGE_FACING_DOT := 0.3
## A defender moving faster than ENGAGE_FOE_MOVING (yd/s) is blocked only when his heading . the
## direction to the blocker reaches ENGAGE_FOE_HEADING_DOT (the blocker is ahead of his path, about
## 78 deg either side): no blocks from behind or on a pair running side by side the same way.
const ENGAGE_FOE_MOVING := 1.0
const ENGAGE_FOE_HEADING_DOT := 0.2
const BLOCK_DRIVE := 0.7       # fraction of defender displacement taken from blocker
const BLOCK_HOLD := 1.5
const BLOCK_IMMUNITY := 0.75
const BLOCKER_BEATEN := 1.5   # after a shed, the blocker cannot re-engage for this long

# Blocking zone (#253): offensive C/OL may not be more than this far past the LOS when a pass is thrown
const BLOCK_ZONE_DEPTH := 5.0            # yd past the LOS; exactly 5 is legal
const BLOCK_ZONE_PENALTY_YARDS := 10.0    # illegal man downfield: yards from the previous spot, down replayed
const AI_BLOCK_ZONE_MARGIN := 1.0        # bot linemen stop this far inside the zone (collisions nudge them)

# AI QB
const AI_QB_THROW_TIME := 2.0
const AI_QB_PASS_POWER := 0.65
const AI_QB_DEPTH_WEIGHT := 0.2
const AI_QB_PRESSURE := 3.0

# Fumbles / loose ball
const FUMBLE_BEHIND_DOT := 0.5      # diver.facing . carrier.facing above this counts as "from behind"
const FUMBLE_HIT_RISK := 0.08       # strip chance of a full-force hit (closing speed DIVE+SPRINT) on a fresh carrier
const FUMBLE_REAR := 0.25           # extra chance for a jogging carrier hit squarely from behind
const FUMBLE_REAR_SPRINT := 0.97    # ...and for a sprinting one (readable: don't sprint with a defender on your back)
const FUMBLE_FRESH_STAMINA := 0.84  # fatigue starts below this stamina
const FUMBLE_FATIGUE_GAIN := 6.0    # exhausted carrier: chance x(1 + gain)
const FUMBLE_MAX_RISK := 0.97
const FUMBLE_KNOCKDOWN := 0.8
const LOOSE_FRICTION := 6.0       # yd/s^2 rolling deceleration
const LOOSE_BOUNCE := 0.35        # vertical restitution
const RECOVER_RADIUS := 0.8
const RECOVER_MAX_HEIGHT := 1.0

# Bots
const NEUTRAL_ZONE_HALF := 0.5     # pre-snap: each side stops this far from the LOS
const STANCE_DOUBLE_TAP := 0.35    # s: a set defender's two Space presses within this break stance (#142)
const BARRIER_HEIGHT := 2.4        # LOS barrier wall height (m)
const BARRIER_REVEAL_DIST := 3.0   # barrier brightens near athletes within this (yd)
const BARRIER_DROP_TIME := 0.3     # barrier dissolve after the snap (s)
const AI_SNAP_DELAY := 2.5         # AI-only offense snaps after this long presnap
const AI_COVER_REACTION := 0.25   # defender reacts to where the receiver was
const AI_COVER_TRAIL := 0.8       # yards behind along the receiver's path
const AI_SPY_DEPTH := 6.0
const AI_DEEP_ZONE := 14.0
const AI_PROTECT_BALL_RANGE := 4.0 # don't sprint with a defender this close
const AI_SPY_BLITZ_TIME := 3.5     # QB still holding it: the spy attacks
const AI_QB_MIN_SEPARATION := 1.5
const AI_QB_MAX_HOLD := 3.2

# Chaosball
const CHAOS_GRAVITY_SCALE := 0.45
const CHAOS_MAX_BOUNCES := 3
const BOUNCE_RESTITUTION := 0.55
const BOUNCE_FRICTION := 0.8
const AI_CHAOS_PRESSURE := 3.5
const LOB_ANGLE := 65.0           # degrees, touch-pass arc
const PASS_CLOCK := 5.0              # Chaosball: ball explodes if held this long
const STREAK_BASE_POINTS := 2
const STREAK_MAX_POINTS := 7
const AI_PASS_CLOCK_MARGIN := 1.2

# Defensive play suggestions
const DEFENSE_GOAL_LINE_RANGE := 5.0
const DEFENSE_PREVENT_DISTANCE := 15.0
const DEFENSE_PREVENT_TIME := 60.0
const DEFENSE_UNDER_DEPTH := 8.0
const DEFENSE_DEEP_DEPTH := 18.0
const DEFENSE_PREVENT_DEPTH := 25.0
const DEFENSE_GOAL_DEPTH := 4.0
const HUDDLE_SECONDS := 5.0
const PROTECTION_RANGE := 8.0

# Kicking (B09/C02). Kicks are deterministic: aim + power meter, no random wobble.
const KICK_SPEED_MIN := 14.0       # yd/s at 0 power
const KICK_SPEED_MAX := 27.0       # yd/s at full power (~66 yd carry)
const KICK_HEIGHT := 0.3           # ball height at contact
const KICK_ANGLE := {"punt": 52.0, "fg": 38.0, "kickoff": 42.0}   # degrees
const KICK_BLOCK_WINDOW := 5.0     # ball travel (yd) during which rushers can block it
const KICK_BLOCK_HEIGHT := 3.0
const KICK_BLOCK_REACH := 1.0
const KICK_REST_TIME := 1.5        # an unfielded kick that stops rolling is downed
const ONSIDE_MIN_TRAVEL := 10.0    # kicking team may recover a kickoff past this
const CROSSBAR_HEIGHT := 3.3
const UPRIGHT_SPAN_FRACTION := 0.116   # of field width, clamped 4.5..6.2 (matches field art)
const PUNT_DEPTH := 10.0           # punter's depth behind the LOS
const FG_HOLD_DEPTH := 7.0         # holder's depth behind the LOS
const KICKOFF_RETURNER_DEPTH := 0.1    # returner stands at this fraction of the field from his goal
const PUNT_RETURNER_DEPTH := 38.0  # yd past the LOS
const KICKOFF_DEFAULT_POWER := 0.85    # Space / play clock kickoff
const AI_FG_MAX := 50.0            # longest field goal (kick distance) a bot tries
const AI_GO_FOR_IT := 2.0          # bots go for it on 4th & this or less past midfield
const AI_FAIR_CATCH_PRESSURE := 5.0    # bot returner fair-catches when coverage is this close to the landing spot (#189)
