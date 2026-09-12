#define SPEED_UPDATE_INTERVAL 5

static float g_fCurrentSpeed[MAXPLAYERS + 1];
static float g_fTickSpeed[MAXPLAYERS + 1];
static int g_iSpeedDirection[MAXPLAYERS + 1];
static int g_iTickNumber;

void Speedometer_Tick(int client, float speed)
{
	g_fTickSpeed[client] = speed;
}

void Speedometer_GameTick()
{
	if(!g_hEnabledSpeedometer.BoolValue)
	{
		return;
	}

	g_iTickNumber++;

	if(g_iTickNumber % SPEED_UPDATE_INTERVAL != 0)
	{
		return;
	}

	g_iTickNumber = 0;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i))
		{
			continue;
		}

		float temp = g_fCurrentSpeed[i];
		g_fCurrentSpeed[i] = IsPlayerAlive(i) ? g_fTickSpeed[i] : 0.0;

		int speedDelta = RoundToFloor(g_fCurrentSpeed[i] - temp);

		int speedColorIdx;

		if(speedDelta > 0)
		{
			speedColorIdx = GainReallyGood;
			g_iSpeedDirection[i] = 1;
		}
		else if (speedDelta == 0)
		{
			speedColorIdx = GainGood;
		}
		else
		{
			speedColorIdx = GainReallyBad;
			g_iSpeedDirection[i] = -1;
		}

		int speed = RoundToFloor(g_fCurrentSpeed[i]);

		for(int j = -1; j < g_iSpecListCurrentFrame[i]; j++)
		{
			int messageTarget = j == -1 ? i:g_iSpecList[i][j];

			bool speedometerEnabled = (g_iSettings[messageTarget][Bools] & SPEEDOMETER_ENABLED) != 0;
			bool smallVelocity = (g_iSettings[messageTarget][Bools] & SPEEDOMETER_SMALL_VELOCITY) != 0;
			if((!speedometerEnabled && !smallVelocity) || !BgsIsValidPlayer(messageTarget))
			{
				continue;
			}

			if(smallVelocity)
			{
				char smallMessage[16];
				Format(smallMessage, sizeof(smallMessage), "%s%i", g_iSpeedDirection[i] < 0 ? "-":"+", speed);
				DisplaySmallVelocity(messageTarget, smallMessage);
			}

			if(!speedometerEnabled)
			{
				continue;
			}

			char message[256];
			if(speed < 10)
			{
				Format(message, sizeof(message), "   %i", speed);
			}
			else if(speed < 10)
			{
				Format(message, sizeof(message), "  %i", speed);
			}
			else if(speed < 1000)
			{
				Format(message, sizeof(message), " %i", speed);
			}
			else
			{
				Format(message, sizeof(message), "%i", speed);
			}

			if(g_iSettings[messageTarget][Bools] & SPEEDOMETER_VELOCITY_DIFF)
			{
				if(speedDelta > 0)
				{
					Format(message, sizeof(message), "%s (+%i)", message, speedDelta);
				}
				else
				{
					Format(message, sizeof(message), "%s (%i)", message, speedDelta);
				}
			}

			BgsDisplayHud(messageTarget, g_fCacheHudPositions[messageTarget][Speedometer], g_iBstatColors[g_iSettings[messageTarget][speedColorIdx]], 0.15, GetDynamicChannel(4), false, message);

		}
	}
}

void DisplaySmallVelocity(int client, const char[] message)
{
	BfWrite center = view_as<BfWrite>(StartMessageOne("TextMsg", client, USERMSG_BLOCKHOOKS));
	center.WriteByte(4);
	center.WriteString(message);
	center.WriteString("");
	center.WriteString("");
	center.WriteString("");
	center.WriteString("");
	center.WriteString("");
	EndMessage();
}
