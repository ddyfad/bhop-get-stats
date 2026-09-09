#include <sdktools>
#include <sdkhooks>
#include <sourcemod>

#undef REQUIRE_PLUGIN
#include <shavit/core>
#include <shavit/replay-playback>
#include <shavit/checkpoints>

bool g_bShavitReplaysLoaded = false;

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "bhop get stats",
	author = "Nimmy",
	description = "central plugin to call bhop stats",
	version = "1.5",
	url = "https://github.com/Nimmy2222/bhop-get-stats"
}

#define BHOP_FRAMES 10
#define YAW 1
#define FORWARDMOVE 0
#define SIDEMOVE 1
#define LEFT 0
#define RIGHT 1

bool g_bTouchesWall[MAXPLAYERS + 1];
bool g_bJumpedThisTick[MAXPLAYERS + 1];
bool g_bOverlap[MAXPLAYERS + 1];
bool g_bNoPress[MAXPLAYERS + 1];
bool g_bSawTurn[MAXPLAYERS + 1];
bool g_bSawPress[MAXPLAYERS + 1];

int g_iTicksOnGround[MAXPLAYERS + 1];
int g_iStrafeTick[MAXPLAYERS + 1];
int g_iSyncedTick[MAXPLAYERS + 1];
int g_iJump[MAXPLAYERS + 1];
int g_iStrafeCount[MAXPLAYERS + 1];
int g_iTurnTick[MAXPLAYERS + 1];
int g_iKeyTick[MAXPLAYERS + 1];
int g_iTurnDir[MAXPLAYERS + 1];
int g_iCmdNum[MAXPLAYERS + 1];
int g_iYawwingTick[MAXPLAYERS + 1];

float g_fOldHeight[MAXPLAYERS + 1];
float g_fRawGain[MAXPLAYERS + 1];
float g_fTrajectory[MAXPLAYERS + 1];
float g_fTraveledDistance[MAXPLAYERS + 1][3];
float g_fRunCmdVelVec[MAXPLAYERS + 1][3];
float g_fLastAngles[MAXPLAYERS + 1][3];
float g_fAvgDiffFromPerf[MAXPLAYERS + 1];
float g_fAvgAbsoluteJss[MAXPLAYERS + 1];
float g_fLastNonZeroMove[MAXPLAYERS + 1][2];
float g_fLastJumpPosition[MAXPLAYERS + 1][3];
float g_fLastVeer[MAXPLAYERS + 1];
float g_fTickrate = 0.01;
float g_fJumpPeak[MAXPLAYERS + 1];

ArrayList g_hReplayFrames[MAXPLAYERS + 1];
int g_iReplayFrame[MAXPLAYERS + 1];

GlobalForward FirstJumpStatsForward;
GlobalForward JumpStatsForward;
GlobalForward StrafeStatsForward;
GlobalForward TickStatsForward;

public void OnPluginStart()
{
	HookEvent("player_jump", Player_Jump);
	g_fTickrate = 1.0 / GetTickInterval();

	g_bShavitReplaysLoaded = LibraryExists("shavit-replay-playback");

	FirstJumpStatsForward = new GlobalForward("BhopStat_FirstJumpForward", ET_Ignore,
	Param_Cell, Param_Cell);
//  int client  int speed

	JumpStatsForward = new GlobalForward("BhopStat_JumpForward", ET_Ignore,
	Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Float, Param_Float, Param_Float, Param_Float, Param_Float, Param_Float, Param_Float, Param_Float);
//  int client, int jump,   int speed, int strafe#, float hPeak, float hDiff, float gain, float sync, float eff,     float yaw%,   float jss   float abs jss

	StrafeStatsForward = new GlobalForward("BhopStat_StrafeForward", ET_Ignore,
	Param_Cell, Param_Cell, Param_Cell, Param_Cell);
//  int client, int offset, bool overlap, bool nopress

	TickStatsForward = new GlobalForward("BhopStat_TickForward", ET_Ignore,
	Param_Cell, Param_Cell, Param_Array, Param_Array, Param_Cell, Param_Float, Param_Float, Param_Float, Param_Float);
//  int client, int buttons, f[3] vel, f[3] angles, bool inbhop, float speed, float gain, float jss, float yawDiff

	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("bhop-get-stats");
	return APLRes_Success;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-replay-playback"))
	{
		g_bShavitReplaysLoaded = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-replay-playback"))
	{
		g_bShavitReplaysLoaded= false;
	}
}

public void OnClientPutInServer(int client)
{
	g_iJump[client] = 0;
	g_iStrafeTick[client] = 0;
	g_iSyncedTick[client] = 0;
	g_fRawGain[client] = 0.0;
	g_fOldHeight[client] = 0.0;
	g_fJumpPeak[client] = 0.0;
	g_fTrajectory[client] = 0.0;
	g_fTraveledDistance[client] = NULL_VECTOR;
	g_iTicksOnGround[client] = 0;
	g_iStrafeCount[client] = 0;
	g_iCmdNum[client] = 0;
	SDKHook(client, SDKHook_Touch, OnTouch);

	if(IsShavitReplayBot(client))
	{
		Bgs_LoadReplayFrames(client);
	}
}

public void OnClientDisconnect(int client)
{
	delete g_hReplayFrames[client];
}

public void Shavit_OnReplayStart(int ent, int type, bool delay_elapsed)
{
	if(ent < 1 || ent > MaxClients)
	{
		return;
	}

	Bgs_LoadReplayFrames(ent);
	Bgs_ResetJumpState(ent);
	g_iTicksOnGround[ent] = 0;
}

public void Shavit_OnReplayEnd(int ent, int type, bool actually_finished)
{
	if(ent < 1 || ent > MaxClients)
	{
		return;
	}

	delete g_hReplayFrames[ent];
}

void Bgs_LoadReplayFrames(int client)
{
	delete g_hReplayFrames[client];
	g_iReplayFrame[client] = Shavit_GetReplayBotCurrentFrame(client);

	ArrayList frames = Shavit_GetReplayFrames(Shavit_GetReplayBotStyle(client), Shavit_GetReplayBotTrack(client), true);
	if(frames == null)
	{
		return;
	}

	int cacheLength = Shavit_GetReplayCacheFrameCount(client) + Shavit_GetReplayCachePreFrames(client) + Shavit_GetReplayCachePostFrames(client);
	if(frames.Length != cacheLength || frames.BlockSize < 8)
	{
		delete frames;
		return;
	}

	g_hReplayFrames[client] = frames;
}

public Action Shavit_OnTeleport(int client, int index, int target)
{
	g_iCmdNum[client] = 0;

	int total = Shavit_GetTotalCheckpoints(target);
	if(index < 1 || index > total)
	{
		return Plugin_Continue;
	}

	cp_cache_t checkPoint;
	Shavit_GetCheckpoint(target, index, checkPoint);
	g_iJump[client] = checkPoint.aSnapshot.iJumps;
	return Plugin_Continue;
}


public Action OnTouch(int client, int entity)
{
	if ((GetEntProp(entity, Prop_Data, "m_usSolidFlags") & 12) == 0)
	{
		g_bTouchesWall[client] = true;
	}
	return Plugin_Continue;
}

public void Player_Jump(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	Bgs_ProcessJump(client);
}

public void Bgs_ProcessJump(int client)
{
	if(g_iJump[client] > 0 && g_iStrafeTick[client] == 0)
	{
		return;
	}

	g_iJump[client]++;
	g_bJumpedThisTick[client] = true;
}

public void OnPlayerRunCmdPre(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if(!IsClientConnected(client) || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	if(IsShavitReplayBot(client))
	{
		return;
	}

	GetEntPropVector(client, Prop_Data, "m_vecVelocity", g_fRunCmdVelVec[client]);

	float origin[3];
	GetClientAbsOrigin(client, origin);

	Bgs_ProcessRunCmd(client, buttons, GetEntityFlags(client), GetEntityMoveType(client), origin);
}

void Bgs_ProcessRunCmd(int client, int buttons, int flags, MoveType movetype, const float origin[3])
{
	//the player jump hook doesnt function on bots, so we use this to call it ourselves
	bool isReplayBot = IsShavitReplayBot(client);

	if(flags & FL_ONGROUND)
	{
		g_iTicksOnGround[client]++;
		if(g_iTicksOnGround[client] >= BHOP_FRAMES)
		{
			if(g_iTicksOnGround[client] == BHOP_FRAMES)
			{
				Bgs_ResetJumpState(client);
			}
			return;
		}

		if ((buttons & IN_JUMP) > 0 && g_iTicksOnGround[client] == 1)
		{
			if(isReplayBot)
			{
				Bgs_ProcessJump(client);
			}

			g_iTicksOnGround[client] = 0;
			//player landed, mustve jumped right?, calc veer
			float xAxisVeer = FloatAbs(origin[0] - g_fLastJumpPosition[client][0]);
			float yAxisVeer = FloatAbs(origin[1] - g_fLastJumpPosition[client][1]);
			g_fLastVeer[client] = xAxisVeer >= yAxisVeer ? yAxisVeer:xAxisVeer; //something about this wrong, kinda close to distbug but not fully, might need to wait till post
		}
	}
	else
	{
		if(isReplayBot && g_iJump[client] == 0 && g_iTicksOnGround[client] > 0)
		{
			Bgs_ProcessJump(client);
		}
		g_iTicksOnGround[client] = 0;
	}

	//move type is not relevant on replay bots
	if(!isReplayBot && (movetype == MOVETYPE_NONE || movetype == MOVETYPE_NOCLIP || movetype == MOVETYPE_LADDER || GetEntProp(client, Prop_Data, "m_nWaterLevel") >= 2))
	{
		g_iTicksOnGround[client] = BHOP_FRAMES + 1;
	}
}

void Bgs_ResetJumpState(int client)
{
	g_iJump[client] = 0;
	g_iStrafeTick[client] = 0;
	g_iSyncedTick[client] = 0;
	g_fRawGain[client] = 0.0;
	g_fTrajectory[client] = 0.0;
	g_iStrafeCount[client] = 0;
	g_fTraveledDistance[client] = NULL_VECTOR;
	g_iCmdNum[client] = 0;
	g_iYawwingTick[client] = 0;
	g_bNoPress[client] = false;
	g_bOverlap[client] = false;
	g_bSawPress[client] = false;
	g_bSawTurn[client] = false;
}

void Bgs_ProcessReplayFrames(int client)
{
	ArrayList frames = g_hReplayFrames[client];
	if(frames == null)
	{
		return;
	}

	int current = Shavit_GetReplayBotCurrentFrame(client);
	int last = g_iReplayFrame[client];
	g_iReplayFrame[client] = current;

	if(current < last || current - last > 2)
	{
		Bgs_ResetJumpState(client);
		g_iTicksOnGround[client] = 0;
		return;
	}

	for(int frame = last + 1; frame <= current && frame < frames.Length; frame++)
	{
		Bgs_ProcessReplayFrame(client, frames, frame);
	}
}

void Bgs_ProcessReplayFrame(int client, ArrayList frames, int index)
{
	frame_t frame;
	frames.GetArray(index, frame, frames.BlockSize);

	frame_t prev;
	prev = frame;
	if(index >= 1)
	{
		frames.GetArray(index - 1, prev, 5);
	}

	float velocity[3];
	if(index >= 2)
	{
		float prevPrevPos[3];
		frames.GetArray(index - 2, prevPrevPos, 3);
		SubtractVectors(prev.pos, prevPrevPos, velocity);
		ScaleVector(velocity, g_fTickrate);
	}

	float vel[3];
	if(frames.BlockSize >= 10)
	{
		int ivel[2];
		UnpackSignedShorts(frame.vel, ivel);
		vel[0] = float(ivel[0]);
		vel[1] = float(ivel[1]);
	}
	else
	{
		if (frame.buttons & IN_FORWARD)   vel[0] = 400.0;
		if (frame.buttons & IN_BACK)      vel[0] -= 400.0;
		if (frame.buttons & IN_MOVERIGHT) vel[1] = 400.0;
		if (frame.buttons & IN_MOVELEFT)  vel[1] -= 400.0;
	}

	float angles[3];
	angles[0] = frame.ang[0];
	angles[1] = frame.ang[1];

	Bgs_ProcessRunCmd(client, frame.buttons, frame.flags, frame.mt, frame.pos);
	Bgs_ProcessPostRunCmd(client, frame.buttons, NormalizeAngle(frame.ang[1] - prev.ang[1]), vel, angles, velocity, frame.pos, 1.0, 0.0, false);
}


public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3])
{
	if(!IsClientConnected(client) || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}

	if(IsShavitReplayBot(client))
	{
		Bgs_ProcessReplayFrames(client);
		return;
	}

	float yawDiff = NormalizeAngle(angles[YAW] - g_fLastAngles[client][YAW]);

	float origin[3];
	GetClientAbsOrigin(client, origin);

	Bgs_ProcessPostRunCmd(client, buttons, yawDiff, vel, angles, g_fRunCmdVelVec[client], origin,
		GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue"), GetEntPropFloat(client, Prop_Send, "m_flMaxspeed"), g_bTouchesWall[client]);
}

void Bgs_ProcessPostRunCmd(int client, int buttons, float yawDiff, const float vel[3], const float angles[3], const float velocity[3], const float origin[3], float speedmulti, float maxspeed, bool touchesWall)
{
	float jssThisTick = 0.0;
	float gaincoeff = 0.0;

	if(g_iTicksOnGround[client] == 0)
	{
		if(origin[2] > g_fJumpPeak[client])
		{
			g_fJumpPeak[client] = origin[2];
		}

		if(yawDiff != 0.0)
		{
			float perfJss = RadToDeg(ArcTangent(30 / GetSpeed(velocity, true)));
			float finalJss = FloatAbs(yawDiff / perfJss);

			g_fAvgDiffFromPerf[client] += finalJss;
			g_fAvgAbsoluteJss[client] += 100 - FloatAbs((finalJss * 100.0) - 100);
			jssThisTick = finalJss;
		}

		if(buttons & IN_LEFT || buttons & IN_RIGHT)
		{
			g_iYawwingTick[client]++;
		}


		//offset shit
		if(g_iCmdNum[client] >= 1)
		{
			if(vel[1] * g_fLastNonZeroMove[client][SIDEMOVE] < 0 || vel[0] * g_fLastNonZeroMove[client][FORWARDMOVE] < 0)
			{
				g_iKeyTick[client] = g_iCmdNum[client];
				g_iStrafeCount[client]++;
				g_bSawPress[client] = true;
			}
		}

		if(yawDiff > 0)
		{
			if(g_iTurnDir[client] == RIGHT && g_iCmdNum[client] > 1)
			{
				g_iTurnTick[client] = g_iCmdNum[client];
				g_bSawTurn[client] = true;
			}

			g_iTurnDir[client] = LEFT;
		}
		else if(yawDiff < 0)
		{
			if(g_iTurnDir[client] == LEFT && g_iCmdNum[client] > 1)
			{
				g_iTurnTick[client] = g_iCmdNum[client];
				g_bSawTurn[client] = true;
			}

			g_iTurnDir[client] = RIGHT;
		}

		bool overlapThisTick = false;
		if(((buttons & IN_MOVELEFT) && (buttons & IN_MOVERIGHT)) || ((buttons & IN_FORWARD) && (buttons & IN_BACK)))
		{
			g_bOverlap[client] = true;
			overlapThisTick = true;
		}

		if(vel[SIDEMOVE] == 0.0 && vel[FORWARDMOVE] == 0.0 && !overlapThisTick)
		{
			g_bNoPress[client] = true;
		}

		if(g_iCmdNum[client] - g_iTurnTick[client] >= 20)
		{
			g_bSawTurn[client] = false;
		}

		if(g_iCmdNum[client] - g_iKeyTick[client] >= 20)
		{
			g_bSawPress[client] = false;
		}

		if(g_bSawPress[client] && g_bSawTurn[client])
		{
			StartStrafeForward(client);
			g_bOverlap[client] = false;
			g_bNoPress[client] = false;
			g_bSawPress[client] = false;
			g_bSawTurn[client] = false;
		}

		g_iStrafeTick[client]++;

		g_fTraveledDistance[client][0] += velocity[0] * g_fTickrate * speedmulti;
		g_fTraveledDistance[client][1] += velocity[1] * g_fTickrate * speedmulti;

		g_fTrajectory[client] += GetSpeed(velocity, true) * g_fTickrate * speedmulti;

		float fore[3];
		float side[3];
		GetAngleVectors(angles, fore, side, NULL_VECTOR);

		fore[2] = 0.0;
		NormalizeVector(fore, fore);

		side[2] = 0.0;
		NormalizeVector(side, side);

		float wishvel[3];
		float wishdir[3];

		for (int i = 0; i < 2; i++)
		{
			wishvel[i] = fore[i] * vel[0] + side[i] * vel[1];
		}

		float wishspeed = NormalizeVector(wishvel, wishdir);

		if(maxspeed != 0.0 && wishspeed > maxspeed)
		{
			wishspeed = maxspeed;
		}

		if(wishspeed > 0.01)
		{
			float wishspd = (wishspeed > 30.0) ? 30.0 : wishspeed;

			float currentgain = 0.0;

			currentgain = GetVectorDotProduct(velocity, wishdir);

			if(currentgain < 30.0)
			{
				gaincoeff = (wishspd - FloatAbs(currentgain)) / wishspd;
				g_iSyncedTick[client]++;
			}

			if(touchesWall && gaincoeff > 0.5)
			{
				gaincoeff -= 1.0;
				gaincoeff = FloatAbs(gaincoeff);
			}

			g_fRawGain[client] += gaincoeff;
		}
		g_iCmdNum[client]++;
	}

	StartTickForward(client, jssThisTick, GetSpeed(velocity, true), yawDiff, gaincoeff, buttons, vel, angles);

	if(g_bTouchesWall[client])
	{
		g_bTouchesWall[client] = false;
	}

	//run order RunCmd -> Jump Hook -> PostCmd | if you compare runcmd and postcmd gain calcs runcmd has 1 extra raw gain tick if you dont wait till here to finalize
	if(g_bJumpedThisTick[client])
	{
		g_fLastJumpPosition[client] = origin;
		g_bJumpedThisTick[client] = false;

		if(g_iJump[client] == 1)
		{
			StartFirstJumpForward(client, velocity);
		}
		else
		{
			StartJumpForward(client, velocity, origin);
		}

		g_fRawGain[client] = 0.0;
		g_iStrafeTick[client] = 0;
		g_iSyncedTick[client] = 0;
		g_iStrafeCount[client] = 0;
		g_fOldHeight[client] = origin[2];
		g_fTrajectory[client] = 0.0;
		g_fTraveledDistance[client] = NULL_VECTOR;
		g_fAvgDiffFromPerf[client] = 0.0;
		g_fAvgAbsoluteJss[client] = 0.0;
	}

	g_fLastAngles[client] = angles;

	if(vel[0] != 0.0 || vel[1] != 0.0)
	{
		g_fLastNonZeroMove[client][0] = vel[0];
		g_fLastNonZeroMove[client][1] = vel[1];
	}

	return;
}


//client, speed, fjt?, jumpoffangle?
void StartFirstJumpForward(int client, const float velocity[3])
{
	Call_StartForward(FirstJumpStatsForward);
	Call_PushCell(client);
	Call_PushCell(RoundToFloor(GetSpeed(velocity, true)));
	Call_Finish();

}

//int client, int jump, int speed, int heightdelta, int strafecount, float gain, float sync, float eff, float yawwing
void StartJumpForward(int client, const float velocity[3], const float origin[3])
{
	int speed = RoundToFloor(GetSpeed(velocity, true));

	float coeffsum = g_fRawGain[client];
	coeffsum /= g_iStrafeTick[client];
	coeffsum *= 100.0;

	float distance = GetVectorLength(g_fTraveledDistance[client]);

	if(distance > g_fTrajectory[client])
	{
		distance = g_fTrajectory[client];
	}

	float efficiency = 0.0;

	if(distance > 0.0)
	{
		efficiency = coeffsum * distance / g_fTrajectory[client];
	}

	coeffsum = RoundToFloor(coeffsum * 100.0 + 0.5) / 100.0;
	efficiency = RoundToFloor(efficiency * 100.0 + 0.5) / 100.0;

	Call_StartForward(JumpStatsForward);
	Call_PushCell(client);
	Call_PushCell(g_iJump[client]);
	Call_PushCell(speed);
	Call_PushCell(g_iStrafeCount[client]);
	Call_PushFloat(g_fJumpPeak[client] - g_fOldHeight[client]);
	Call_PushFloat(origin[2] - g_fOldHeight[client]);
	Call_PushFloat(coeffsum);
	Call_PushFloat(100.0 * g_iSyncedTick[client] / g_iStrafeTick[client]);
	Call_PushFloat(efficiency);
	Call_PushFloat(100.0 * g_iYawwingTick[client] / g_iStrafeTick[client]);
	Call_PushFloat(g_fAvgDiffFromPerf[client] / g_iStrafeTick[client]);
	Call_PushFloat(g_fAvgAbsoluteJss[client] / g_iStrafeTick[client]);
	Call_Finish();
}

//int client, int offset, bool overlap, bool nopress
void StartStrafeForward(int client)
{
	Call_StartForward(StrafeStatsForward);
	Call_PushCell(client);
	Call_PushCell(g_iKeyTick[client] - g_iTurnTick[client]);
	Call_PushCell(view_as<int>(g_bOverlap[client]));
	Call_PushCell(view_as<int>(g_bNoPress[client]));
	Call_Finish();
}

//int client, int buttons, f[3] vel, f[3] angles, bool inbhop, f speed, f gain, f jss, f yawDiff
void StartTickForward(int client, float jssThisTick, float speed, float yawDiff, float tickGain, int buttons, const float vel[3], const float angles[3])
{
	Call_StartForward(TickStatsForward);
	Call_PushCell(client);
	Call_PushCell(buttons);
	Call_PushArray(vel, 3);
	Call_PushArray(angles, 3);
	Call_PushCell(view_as<int>((g_iTicksOnGround[client] == 0)));
	Call_PushFloat(speed);
	Call_PushFloat(tickGain);
	Call_PushFloat(jssThisTick);
	Call_PushFloat(yawDiff);
	Call_Finish();
}

float GetSpeed(const float vel[3], bool twoD)
{
	float velCopy[3];
	velCopy = vel;
	if(twoD)
	{
		velCopy[2] = 0.0;
	}
	return GetVectorLength(velCopy);
}

float NormalizeAngle(float ang)
{
	while (ang > 180.0)
	{
		ang -= 360.0;
	}

	while (ang < -180.0)
	{
		ang += 360.0;
	}
	return ang;
}

bool IsShavitReplayBot(int client)
{
	return g_bShavitReplaysLoaded && IsFakeClient(client) && Shavit_IsReplayEntity(client);
}
