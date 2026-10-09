using System;
using System.Collections.Generic;
using System.Text;
using Godot;
using MegaCrit.Sts2.Core.Localization;
using MegaCrit.Sts2.Core.Platform.Steam;
using Steamworks;

namespace MegaCrit.Sts2.Core.Entities.Multiplayer;

/// <summary>
/// Contains information about why a network operation failed, or why we disconnected from a multiplayer session.
/// Prefer passing this instead of NetError, as this contains more information about the underlying error that might
/// have been mapped to our NetError.
/// </summary>
public readonly struct NetErrorInfo
{
	private readonly NetError? _reason;

	private readonly ConnectionFailureReason? _connectionReason;

	private readonly ConnectionFailureExtraInfo? _connectionExtraInfo;

	private readonly SteamDisconnectionReason? _steamReason;

	private readonly EResult? _lobbyCreationResult;

	private readonly EChatRoomEnterResponse? _lobbyEnterResponse;

	private readonly string? _debugReason;

	private readonly Error? _godotError;

	public bool SelfInitiated { get; }

	public NetErrorInfo(NetError reason, bool selfInitiated)
	{
		_connectionReason = null;
		_connectionExtraInfo = null;
		_steamReason = null;
		_lobbyCreationResult = null;
		_lobbyEnterResponse = null;
		_debugReason = null;
		_godotError = null;
		_reason = reason;
		SelfInitiated = selfInitiated;
	}

	public NetErrorInfo(ConnectionFailureReason reason, ConnectionFailureExtraInfo? extraInfo = null)
	{
		_reason = null;
		_steamReason = null;
		_lobbyCreationResult = null;
		_lobbyEnterResponse = null;
		_debugReason = null;
		_godotError = null;
		_connectionReason = reason;
		_connectionExtraInfo = extraInfo;
		SelfInitiated = false;
	}

	public NetErrorInfo(SteamDisconnectionReason steamReason, string? debugReason, bool selfInitiated)
	{
		_reason = null;
		_connectionReason = null;
		_connectionExtraInfo = null;
		_lobbyCreationResult = null;
		_lobbyEnterResponse = null;
		_godotError = null;
		_steamReason = steamReason;
		_debugReason = debugReason;
		SelfInitiated = selfInitiated;
	}

	public NetErrorInfo(EChatRoomEnterResponse lobbyEnterResponse)
	{
		_reason = null;
		_connectionReason = null;
		_connectionExtraInfo = null;
		_steamReason = null;
		_lobbyCreationResult = null;
		_debugReason = null;
		_godotError = null;
		_lobbyEnterResponse = lobbyEnterResponse;
		SelfInitiated = true;
	}

	public NetErrorInfo(EResult lobbyCreationResult)
	{
		_reason = null;
		_connectionReason = null;
		_connectionExtraInfo = null;
		_steamReason = null;
		_lobbyEnterResponse = null;
		_debugReason = null;
		_godotError = null;
		_lobbyCreationResult = lobbyCreationResult;
		SelfInitiated = true;
	}

	public NetErrorInfo(Error error)
	{
		_reason = null;
		_connectionReason = null;
		_connectionExtraInfo = null;
		_steamReason = null;
		_lobbyCreationResult = null;
		_lobbyEnterResponse = null;
		_debugReason = null;
		_godotError = error;
		SelfInitiated = true;
	}

	/// <summary>
	/// Returns a disconnection reason mapped from the underlying transport disconnection reason.
	/// </summary>
	public NetError GetReason()
	{
		if (_reason.HasValue)
		{
			return _reason.Value;
		}
		if (_connectionReason.HasValue)
		{
			ConnectionFailureReason value = _connectionReason.Value;
			return value switch
			{
				ConnectionFailureReason.None => NetError.None, 
				ConnectionFailureReason.LobbyFull => NetError.LobbyFull, 
				ConnectionFailureReason.RunInProgress => NetError.RunInProgress, 
				ConnectionFailureReason.NotInSaveGame => NetError.NotInSaveGame, 
				ConnectionFailureReason.VersionMismatch => NetError.VersionMismatch, 
				ConnectionFailureReason.ModMismatch => NetError.ModMismatch, 
			};
		}
		if (_steamReason.HasValue)
		{
			return _steamReason.Value.ToApp();
		}
		if (_lobbyCreationResult.HasValue)
		{
			return NetError.FailedToHost;
		}
		if (_lobbyEnterResponse.HasValue)
		{
			EChatRoomEnterResponse value2 = _lobbyEnterResponse.Value;
			return value2 switch
			{
				EChatRoomEnterResponse.k_EChatRoomEnterResponseDoesntExist => NetError.InvalidJoin, 
				EChatRoomEnterResponse.k_EChatRoomEnterResponseNotAllowed => NetError.InternalError, 
				EChatRoomEnterResponse.k_EChatRoomEnterResponseFull => NetError.LobbyFull, 
				EChatRoomEnterResponse.k_EChatRoomEnterResponseError => NetError.UnknownNetworkError, 
				EChatRoomEnterResponse.k_EChatRoomEnterResponseBanned => NetError.JoinBlockedByUser, 
				EChatRoomEnterResponse.k_EChatRoomEnterResponseLimited => NetError.UnknownNetworkError, 
				EChatRoomEnterResponse.k_EChatRoomEnterResponseClanDisabled => NetError.JoinBlockedByUser, 
				EChatRoomEnterResponse.k_EChatRoomEnterResponseCommunityBan => NetError.JoinBlockedByUser, 
				EChatRoomEnterResponse.k_EChatRoomEnterResponseMemberBlockedYou => NetError.JoinBlockedByUser, 
				EChatRoomEnterResponse.k_EChatRoomEnterResponseYouBlockedMember => NetError.JoinBlockedByUser, 
				EChatRoomEnterResponse.k_EChatRoomEnterResponseRatelimitExceeded => NetError.RateLimited, 
				EChatRoomEnterResponse.k_EChatRoomEnterResponseSuccess => NetError.None, 
			};
		}
		if (_godotError.HasValue)
		{
			return NetError.FailedToHost;
		}
		throw new InvalidOperationException("Tried to get DisconnectionReason from DisconnectionInfo without any assigned errors");
	}

	/// <summary>
	/// Returns a string with more human-readable details about the underlying cause of the disconnection.
	/// This is suitable for displaying to users as long as platform requirements allow plain error codes in messages.
	/// </summary>
	public string GetErrorString()
	{
		if (_reason.HasValue)
		{
			return _reason.Value.ToString();
		}
		if (_connectionReason.HasValue)
		{
			if (_connectionReason == ConnectionFailureReason.ModMismatch)
			{
				StringBuilder stringBuilder = new StringBuilder();
				List<string> list = _connectionExtraInfo?.missingModsOnHost;
				if (list != null && list.Count > 0)
				{
					LocString locString = new LocString("main_menu_ui", "NETWORK_ERROR.MOD_MISMATCH.description.missingOnHost");
					locString.Add("mods", string.Join(", ", _connectionExtraInfo.missingModsOnHost));
					stringBuilder.AppendLine(locString.GetFormattedText());
				}
				list = _connectionExtraInfo?.missingModsOnLocal;
				if (list != null && list.Count > 0)
				{
					LocString locString2 = new LocString("main_menu_ui", "NETWORK_ERROR.MOD_MISMATCH.description.missingOnLocal");
					locString2.Add("mods", string.Join(", ", _connectionExtraInfo.missingModsOnLocal));
					stringBuilder.AppendLine(locString2.GetFormattedText());
				}
				return stringBuilder.ToString();
			}
			return _connectionReason.Value.ToString();
		}
		if (_steamReason.HasValue)
		{
			return $"{_steamReason} - {_debugReason}";
		}
		if (_lobbyCreationResult.HasValue)
		{
			return $"Lobby creation failed: {_lobbyCreationResult.Value}";
		}
		if (_lobbyEnterResponse.HasValue)
		{
			return $"Lobby join failed: {_lobbyEnterResponse.Value}";
		}
		if (_godotError.HasValue)
		{
			return _godotError.Value.ToString();
		}
		return "<null>";
	}

	/// <summary>
	/// Returns a string that should not be displayed to the user. Use this in debug logs.
	/// </summary>
	public override string ToString()
	{
		if (_reason.HasValue)
		{
			return $"DisconnectionReason {_reason.Value} {SelfInitiated}";
		}
		if (_connectionReason.HasValue)
		{
			return $"ConnectionFailureReason {_connectionReason.Value} {SelfInitiated}";
		}
		if (_steamReason.HasValue)
		{
			return $"SteamDisconnectionReason {_steamReason.Value} {_debugReason} {SelfInitiated}";
		}
		if (_lobbyCreationResult.HasValue)
		{
			return $"EResult {_lobbyCreationResult.Value} {SelfInitiated}";
		}
		if (_lobbyEnterResponse.HasValue)
		{
			return $"EChatRoomEnterResponse {_lobbyEnterResponse.Value} {SelfInitiated}";
		}
		if (_godotError.HasValue)
		{
			return $"Godot.Error {_godotError.Value} {SelfInitiated}";
		}
		return "<null>";
	}
}
