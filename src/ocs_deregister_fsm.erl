%%% ocs_deregister_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2020 SigScale Global Inc.
%%% @end
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc This {@link //stdlib/gen_fsm. gen_fsm} behaviour callback module
%%% 	implements procedures for deregistration of user equipment (UE) in
%%% 	non-3GPP access networks.
%%%
%%% @reference <a href="https://webapp.etsi.org/key/key.asp?GSMSpecPart1=29&amp;GSMSpecPart2=273">
%%% 	3GPP TS 29.273 - 3GPP EPS AAA interfaces</a>
%%%
-module(ocs_deregister_fsm).
-copyright('Copyright (c) 2016 - 2020 SigScale Global Inc.').

-behaviour(gen_fsm).

%% export the ocs_deregister_fsm API
-export([]).

%% export the ocs_deregister_fsm state callbacks
-export([idle/3, abort/2]).

%% export the call backs needed for gen_fsm behaviour
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
			terminate/3, code_change/4]).

-include("ocs.hrl").
-include("diameter_gen_3gpp.hrl").
-include("diameter_3gpp.hrl").
-include("diameter_gen_3gpp_sta_application.hrl").
-include("diameter_gen_3gpp_swm_application.hrl").
-include("diameter_gen_3gpp_swx_application.hrl").
-include_lib("radius/include/radius.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").

-record(statedata,
		{identity :: binary() | undefined,
		origin_host :: binary(),
		origin_realm :: binary(),
		server_address :: inet:ip_address(),
		server_port :: pos_integer(),
		client_address :: undefined | inet:ip_address(),
		client_port :: undefined | pos_integer(),
		service :: tuple() | undefined,
		hss_realm :: string() | undefined,
		hss_host :: string() | undefined,
		nas_host :: string() | undefined,
		nas_realm :: string() | undefined,
		nas_address :: inet:ip_address() | undefined,
		application :: pos_integer() | undefined,
		request :: #'3gpp_swx_RTR'{},
		session_id :: string(),
		session_index :: string() | undefined,
		from :: {pid(), reference()} | undefined}).
-type statedata() :: #statedata{}.

-define(IANA_PEN_3GPP, 10415).
-define(STa_APPLICATION_ID, 16777250).
-define(SWm_APPLICATION_ID, 16777264).
-define(SWx_APPLICATION_ID, 16777265).
-define(STa_APPLICATION, ocs_diameter_3gpp_sta_application).
-define(SWm_APPLICATION, ocs_diameter_3gpp_swm_application).
-define(SWx_APPLICATION, ocs_diameter_3gpp_swx_application).

-define(TIMEOUT, 5000).

%% support deprecated_time_unit()
-define(MILLISECOND, milli_seconds).
%-define(MILLISECOND, millisecond).

%%----------------------------------------------------------------------
%%  The ocs_deregister_fsm API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The ocs_deregister_fsm gen_fsm call backs
%%----------------------------------------------------------------------

-spec init(Args) -> Result
	when
		Args :: list(),
		Result :: {ok, StateName, StateData}
		| {ok, StateName, StateData, Timeout}
		| {ok, StateName, StateData, hibernate}
		| {stop, Reason} | ignore,
		StateName :: atom(),
		StateData :: statedata(),
		Timeout :: non_neg_integer() | infinity,
		Reason :: term().
%% @doc Initialize the {@module} finite state machine.
%% @see //stdlib/gen_fsm:init/1
%% @private
%%
init([ServiceName, ServerAddress, ServerPort, ClientAddress,
		ClientPort, SessionId, OriginHost, OriginRealm,
		DestinationHost, DestinationRealm] = _Args) ->
	process_flag(trap_exit, true),
	{ok, idle, #statedata{service = ServiceName, session_id = SessionId,
			server_address = ServerAddress, server_port = ServerPort,
			client_address = ClientAddress, client_port = ClientPort,
			origin_host = OriginHost, origin_realm = OriginRealm,
			hss_realm = DestinationRealm, hss_host = DestinationHost}}.

-spec idle(Event, From, StateData) -> Result
	when
		Event :: timeout | term(),
		From :: {pid(), reference()},
		StateData :: statedata(),
		Result :: {reply, Reply, NextStateName, NewStateData}
			| {reply, Reply, NextStateName, NewStateData, Timeout}
			| {reply, Reply, NextStateName, NewStateData, hibernate}
			| {next_state, NextStateName, NewStateData}
			| {next_state, NextStateName, NewStateData, Timeout}
			| {next_state, NextStateName, NewStateData, hibernate}
			| {stop, Reason, Reply, NewStateData}
			| {stop, Reason, NewStateData},
		Reply :: term(),
		NextStateName :: atom(),
		NewStateData :: statedata(),
		Timeout :: non_neg_integer() | infinity,
		Reason :: normal | term().
%% @doc Handle events sent with {@link //stdlib/gen_fsm:sync_send_event/2.
%%		gen_fsm:sync_send_event/2} in the <b>idle</b> state.
%% @@see //stdlib/gen_fsm:StateName/3
%% @private
%%
idle(#'3gpp_swx_RTR'{'User-Name' = [Identity]} = Request,
		From, #statedata{session_id = SessionId, hss_host = HssHost,
		hss_realm = HssRealm} = StateData) ->
	F = fun() ->
			mnesia:index_read(session, Identity, #session.imsi)
	end,
	case mnesia:transaction(F) of
		{atomic, [#session{id = AccessSessionId, imsi = Identity,
				application = undefined, nas_address = NasAddress}]} ->
			NewStateData = StateData#statedata{request = Request,
					session_index = AccessSessionId, identity = Identity,
					nas_address = NasAddress, from = From},
			start_radius_disconnect(NewStateData),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			Reply = response(ResultCode, NewStateData),
			{stop, shutdown,  Reply, NewStateData};
		{atomic, [#session{id = AccessSessionId, imsi = Identity,
				application = Application, nas_address = undefined,
				nas_host = NasHost, nas_realm = NasRealm}]} ->
			NewStateData = StateData#statedata{request = Request,
					session_index = AccessSessionId, identity = Identity,
					application = Application, nas_host = NasHost,
					nas_realm = NasRealm, from = From},
			send_abort(NewStateData),
			{next_state, abort, NewStateData, ?TIMEOUT};
		{atomic, []} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNKNOWN_SESSION_ID',
			Reply = response(ResultCode, StateData),
			{stop, shutdown,  Reply, StateData};
		{aborted, Reason} ->
			error_logger:error_report(["Failed user lookup",
					{hss_host, HssHost}, {hss_realm, HssRealm},
					{imsi, Identity}, {session, SessionId},
					{error, Reason}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = response(ResultCode, StateData),
			{stop, shutdown,  Reply, StateData}
	end.

-spec abort(Event, StateData) -> Result
	when
		Event :: timeout | term(),
		StateData :: statedata(),
		Result :: {next_state, NextStateName, NewStateData}
				| {next_state, NextStateName, NewStateData, Timeout}
				| {next_state, NextStateName, NewStateData, hibernate}
				| {stop, Reason, NewStateData},
		NextStateName :: atom(),
		NewStateData :: statedata(),
		Timeout :: non_neg_integer() | infinity,
		Reason :: normal | term().
%% @doc Handle events sent with {@link //stdlib/gen_fsm:send_event/2.
%%		gen_fsm:send_event/2} in the <b>abort</b> state.
%% @@see //stdlib/gen_fsm:StateName/2
%% @private
%%
abort({ok, #'3gpp_sta_ASA'{'Result-Code' = [?'DIAMETER_BASE_RESULT-CODE_SUCCESS']}},
		#statedata{from = Caller} = StateData) ->
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
	gen_fsm:reply(Caller, response(ResultCode, StateData)),
	{stop, shutdown, StateData};
abort({ok, #'3gpp_swm_ASA'{'Result-Code' = [?'DIAMETER_BASE_RESULT-CODE_SUCCESS']}},
		#statedata{from = Caller} = StateData) ->
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
	gen_fsm:reply(Caller, response(ResultCode, StateData)),
	{stop, shutdown, StateData};
abort({ok, #'3gpp_sta_ASA'{'Result-Code' = [?'DIAMETER_ERROR_USER_UNKNOWN']}},
		#statedata{from = Caller} = StateData) ->
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNKNOWN_SESSION_ID',
	gen_fsm:reply(Caller, response(ResultCode, StateData)),
	{stop, shutdown, StateData};
abort({ok, #'3gpp_swm_ASA'{'Result-Code' = [?'DIAMETER_ERROR_USER_UNKNOWN']}},
		#statedata{from = Caller} = StateData) ->
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNKNOWN_SESSION_ID',
	gen_fsm:reply(Caller, response(ResultCode, StateData)),
	{stop, shutdown, StateData}.

-spec handle_event(Event, StateName, StateData) -> Result
	when
		Event :: term(),
		StateName :: atom(),
      StateData :: statedata(),
		Result :: {next_state, NextStateName, NewStateData}
				| {next_state, NextStateName, NewStateData, Timeout}
				| {next_state, NextStateName, NewStateData, hibernate}
				| {stop, Reason, NewStateData},
		NextStateName :: atom(),
		NewStateData :: statedata(),
		Timeout :: non_neg_integer() | infinity,
		Reason :: normal | term().
%% @doc Handle an event sent with
%% 	{@link //stdlib/gen_fsm:send_all_state_event/2.
%% 	gen_fsm:send_all_state_event/2}.
%% @see //stdlib/gen_fsm:handle_event/3
%% @private
%%
handle_event(Event, _StateName, StateData) ->
	{stop, Event, StateData}.

-spec handle_sync_event(Event, From, StateName, StateData) -> Result
	when
		Event :: term(),
		From :: {Pid, Tag},
		Pid :: pid(),
		Tag :: term(),
      StateName :: atom(),
		StateData :: statedata(),
		Result :: {reply, Reply, NextStateName, NewStateData}
			| {reply, Reply, NextStateName, NewStateData, Timeout}
			| {reply, Reply, NextStateName, NewStateData, hibernate}
			| {next_state, NextStateName, NewStateData}
			| {next_state, NextStateName, NewStateData, Timeout}
			| {next_state, NextStateName, NewStateData, hibernate}
			| {stop, Reason, Reply, NewStateData}
			| {stop, Reason, NewStateData},
		Reply :: term(),
		NextStateName ::atom(),
		NewStateData :: statedata(),
		Timeout :: non_neg_integer() | infinity,
		Reason :: normal | term().
%% @doc Handle an event sent with
%% 	{@link //stdlib/gen_fsm:sync_send_all_state_event/2.
%% 	gen_fsm:sync_send_all_state_event/2,3}.
%% @see //stdlib/gen_fsm:handle_sync_event/4
%% @private
%%
handle_sync_event(Event, _From, _StateName, StateData) ->
	{stop, Event, StateData}.

-spec handle_info(Info, StateName, StateData) -> Result
	when
		Info :: term(),
		StateName :: atom(),
		StateData :: statedata(),
		Result :: {next_state, NextStateName, NewStateData}
				| {next_state, NextStateName, NewStateData, Timeout}
		| {next_state, NextStateName, NewStateData, hibernate}
		| {stop, Reason, NewStateData},
		NextStateName :: atom(),
		NewStateData :: statedata(),
		Timeout :: non_neg_integer() | infinity,
		Reason :: normal | term().
%% @doc Handle a received message.
%% @see //stdlib/gen_fsm:handle_info/3
%% @private
%%
handle_info(Info, request, StateData) ->
	{stop, Info, StateData}.

-spec terminate(Reason, StateName, StateData) -> any()
	when
		Reason :: normal | shutdown | term(),
		StateName :: atom(),
      StateData :: statedata().
%% @doc Cleanup and exit.
%% @see //stdlib/gen_fsm:terminate/3
%% @private
%%
terminate(_Reason, _StateName, _StateData) ->
	ok.

-spec code_change(OldVsn, StateName, StateData, Extra ) -> Result
	when
		OldVsn :: (Vsn | {down, Vsn}),
		Vsn :: term(),
      StateName :: atom(),
		StateData :: statedata(),
		Extra :: term(),
		Result :: {ok, NextStateName, NewStateData},
		NextStateName :: atom(),
		NewStateData :: statedata().
%% @doc Update internal state data during a release upgrade&#047;downgrade.
%% @see //stdlib/gen_fsm:code_change/4
%% @private
%%
code_change(_OldVsn, StateName, StateData, _Extra) ->
	{ok, StateName, StateData}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec response(ResultCode, StateData) -> Result
	when
		ResultCode :: pos_integer(),
		StateData :: #statedata{},
		Result :: #'3gpp_swx_RTA'{}.
%% @doc Create DIAMETER response.
%% @hidden
response(ResultCode,
		#statedata{request = #'3gpp_swx_RTR'{} = Request,
		session_id = SessionId,
		server_address = ServerAddress, server_port = ServerPort,
		client_address = ClientAddress, client_port = ClientPort,
		origin_host = OriginHost, origin_realm = OriginRealm} = _StateData)
		when is_integer(ResultCode), is_binary(OriginHost),
		is_binary(OriginRealm) ->
	Server = {ServerAddress, ServerPort},
	Client = {ClientAddress, ClientPort},
	Answer = #'3gpp_swx_RTA'{'Session-Id' = SessionId,
			'Result-Code' = ResultCode,
			'Origin-Host' = OriginHost,
			'Origin-Realm' = OriginRealm},
	ok = ocs_log:auth_log(diameter, Server, Client, Request, Answer),
	Answer.

-spec send_abort(StateData) -> Result
	when
		StateData :: #statedata{},
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Send DIAMETER Abort-Session-Reqest (ASR).
%% @hidden
send_abort(#statedata{application = ?STa_APPLICATION_ID,
		session_index = SessionId, identity = Identity,
		origin_host = OriginHost, origin_realm = OriginRealm,
		nas_host = NasHost, nas_realm = NasRealm,
		service = Service} = _StateData) ->
	Request = #'3gpp_sta_ASR'{'Session-Id' = SessionId,
			'User-Name' = [Identity], 'Origin-Realm' = OriginRealm,
			'Origin-Host' = OriginHost, 'Destination-Realm' = NasRealm,
			'Destination-Host' = NasHost,
			'Auth-Session-State' = ?'DIAMETER_BASE_AUTH-SESSION-STATE_NO_STATE_MAINTAINED'},
	diameter:call(Service, ?STa_APPLICATION,
			Request, [detach, {extra, [self()]}]);
send_abort(#statedata{application = ?SWm_APPLICATION_ID,
		session_index = SessionId, identity = Identity,
		origin_host = OriginHost, origin_realm = OriginRealm,
		nas_host = NasHost, nas_realm = NasRealm,
		service = Service} = _StateData) ->
	Request = #'3gpp_swm_ASR'{'Session-Id' = SessionId,
			'User-Name' = [Identity], 'Origin-Realm' = OriginRealm,
			'Origin-Host' = OriginHost, 'Destination-Realm' = NasRealm,
			'Destination-Host' = NasHost,
			'Auth-Session-State' = ?'DIAMETER_BASE_AUTH-SESSION-STATE_NO_STATE_MAINTAINED'},
	diameter:call(Service, ?SWm_APPLICATION,
			Request, [detach, {extra, [self()]}]).

-spec start_radius_disconnect(StateData) -> Result
	when
		StateData :: #statedata{},
		Result :: ok | {ok, pid()}.
%% @doc Start a RADIUS disconnect.
%% @hidden
start_radius_disconnect(#statedata{session_index = SessionId,
		identity = Identity, nas_address = Address} = _StateData) ->
	case pg2:get_closest_pid(ocs_radius_acct_port_sup) of
		{error, Reason} ->
			error_logger:error_report(["Failed to initiate session disconnect",
					{module, ?MODULE}, {imsi, Identity}, {address, Address},
					{session, SessionId}, {error, Reason}]);
		DiscSup ->
			DiscArgs = [Identity, SessionId],
			StartArgs = [DiscArgs, []],
			supervisor:start_child(DiscSup, StartArgs)
	end.

