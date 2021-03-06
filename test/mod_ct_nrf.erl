%%% mod_ct_nrf.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021 SigScale Global Inc.
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
%%%
-module(mod_ct_nrf).
-copyright('Copyright (c) 2021 SigScale Global Inc.').

-export([do/1]).

-include_lib("inets/include/httpd.hrl").

%% support deprecated_time_unit()
-define(MILLISECOND, milli_seconds).
%-define(MILLISECOND, millisecond).

-spec do(ModData) -> Result when
	ModData :: #mod{},
	Result :: {proceed, OldData} | {proceed, NewData} | {break, NewData} | done,
	OldData :: list(),
	NewData :: [{response,{StatusCode,Body}}] | [{response,{response,Head,Body}}]
			| [{response,{already_sent,StatusCode,Size}}],
	StatusCode :: integer(),
	Body :: iolist() | nobody | {Fun, Arg},
	Head :: [HeaderOption],
	HeaderOption :: {Option, Value} | {code, StatusCode},
	Option :: accept_ranges | allow
			| cache_control | content_MD5
			| content_encoding | content_language
			| content_length | content_location
			| content_range | content_type | date
			| etag | expires | last_modified
			| location | pragma | retry_after
			| server | trailer | transfer_encoding,
	Value :: string(),
	Size :: term(),
	Fun :: fun((Arg) -> sent| close | Body),
	Arg :: [term()].
%% @doc Erlang web server API callback function.
do(#mod{method = Method, parsed_header = Headers, request_uri = Uri,
		entity_body = Body, data = Data} = ModData) ->
	case Method of
		"POST" ->
			case proplists:get_value(status, Data) of
				{_StatusCode, _PhraseArgs, _Reason} ->
					{proceed, Data};
				undefined ->
					case proplists:get_value(response, Data) of
						undefined ->
							Path = http_uri:decode(Uri),
							content_type_available(Headers, Path, Body, ModData);
						_Response ->
							{proceed,  Data}
					end
			end;
		_ ->
			{proceed, Data}
	end.

%% @hidden
content_type_available(Headers, Uri, Body, #mod{data = Data} = ModData) ->
	case lists:keyfind("accept", 1, Headers) of
		{_, "application/json"} ->
			do_post(ModData, Body, string:tokens(Uri, "/"));
		{_, _} ->
			Response = "<h2>HTTP Error 415 - Unsupported Media Type</h2>",
			{proceed, [{response, {415, Response}} | Data]};
		_ ->
			do_response(ModData, {error, 400})
	end.

%% @hidden
do_post(ModData, Body, ["ratingdata"]) ->
	try
		{struct, NrfRequest} = mochijson:decode(Body),
		{_, InvocationSequenceNumber} = lists:keyfind("invocationSequenceNumber", 1, NrfRequest),
		{_, {_, ServiceRatingRequests}} = lists:keyfind("serviceRating", 1, NrfRequest),
		true = length(ServiceRatingRequests) > 0,
		TS = erlang:system_time(?MILLISECOND),
		InvocationTimeStamp = ocs_log:iso8601(TS),
		ServiceRatingResults = service_rating(ServiceRatingRequests, []),
		SubscriptionId = lists:keyfind("subscriptionId", 1, NrfRequest),
		Response = {struct,[{"invocationTimeStamp", InvocationTimeStamp},
				{"invocationSequenceNumber", InvocationSequenceNumber},
				SubscriptionId,
				{"serviceRating",
				{array, ServiceRatingResults}}]},
		RatingDataRef = integer_to_list(rand:uniform(16#ffff)),
		Headers = [{location, "/ratingdata/" ++ RatingDataRef}],
		do_response(ModData, {201, Headers, mochijson:encode(Response)})
	catch
		_:_Reason ->
			do_response(ModData, {error, 400})
	end;
do_post(ModData, Body, ["ratingdata", _RatingDataRef, Op])
		when Op == "update"; Op == "release" ->
	try
		{struct, NrfRequest} = mochijson:decode(Body),
		{_, InvocationSequenceNumber} = lists:keyfind("invocationSequenceNumber", 1, NrfRequest),
		{_, {_, ServiceRatingRequests}} = lists:keyfind("serviceRating", 1, NrfRequest),
		true = length(ServiceRatingRequests) > 0,
		TS = erlang:system_time(?MILLISECOND),
		InvocationTimeStamp = ocs_log:iso8601(TS),
		ServiceRatingResults = service_rating(ServiceRatingRequests, []),
		SubscriptionId = lists:keyfind("subscriptionId", 1, NrfRequest),
		Response = {struct,[{"invocationTimeStamp", InvocationTimeStamp},
				{"invocationSequenceNumber", InvocationSequenceNumber},
				SubscriptionId,
				{"serviceRating",
				{array, ServiceRatingResults}}]},
		do_response(ModData, {200, [], mochijson:encode(Response)})
	catch
		_:_Reason ->
			do_response(ModData, {error, 400})
	end.

service_rating([{_, Attributes} | T], Acc) ->
	NewAttributes1 = case lists:keyfind("serviceContextId", 1, Attributes) of
		false ->
			[];
		ServiceContextId ->
			[ServiceContextId]
	end,
	NewAttributes2 = case lists:keyfind("serviceId", 1, Attributes) of
		false ->
			NewAttributes1;
		ServiceId ->
			[ServiceId | NewAttributes1]
	end,
	NewAttributes3 = case lists:keyfind("ratingGroup", 1, Attributes) of
		false ->
			NewAttributes2;
		RatingGroup ->
			[RatingGroup | NewAttributes2]
	end,
	NewAttributes4 = case lists:keyfind("requestedUnit", 1, Attributes) of
		false ->
			NewAttributes3;
		{"requestedUnit", {struct, RequestedUnits}} ->
			[{"grantedUnit", {struct, RequestedUnits}} | NewAttributes3]
	end,
	NewAttributes5 = case lists:keyfind("consumedUnit", 1, Attributes) of
		false ->
			NewAttributes4;
		{"consumedUnit", {struct, ConsumedUnits}} ->
			[{"consumedUnit", {struct, ConsumedUnits}} | NewAttributes4]
	end,
	NewAttributes6 = case lists:keyfind("requestSubType", 1, Attributes) of
		false ->
			NewAttributes5;
		{_, "RESERVE"} ->
			[{"resultCode", "SUCCESS"} | NewAttributes5];
		{_, "DEBIT"} ->
			[{"resultCode", "SUCCESS"} | NewAttributes5]
	end,
	case NewAttributes6 of
		[] ->
			service_rating(T, Acc);
		NewAttributes6 when length(NewAttributes6) > 0 ->
			service_rating(T, [{struct, NewAttributes6} | Acc])
	end;
service_rating([], Acc) ->
	Acc.

%% @hidden
do_response(#mod{data = Data} = ModData, {Code, Headers, ResponseBody}) ->
	Size = integer_to_list(iolist_size(ResponseBody)),
	NewHeaders = Headers ++ [{content_length, Size},
			{content_type, "application/json"}],
	send(ModData, Code, NewHeaders, ResponseBody),
	{proceed,[{response,{already_sent, Code, Size}} | Data]};
do_response(#mod{data = Data} = _ModData, {error, 400}) ->
	Response = "<h2>HTTP Error 400 - Bad Request</h2>",
	{proceed, [{response, {400, Response}} | Data]}.

%% @hidden
send(#mod{socket = Socket, socket_type = SocketType} = Info,
		StatusCode, Headers, ResponseBody) ->
	httpd_response:send_header(Info, StatusCode, Headers),
	httpd_socket:deliver(SocketType, Socket, ResponseBody).

