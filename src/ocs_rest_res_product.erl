%%% ocs_rest_res_product.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2017 SigScale Global Inc.
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
%%% @doc This library module implements resource handling functions
%%% 	for a REST server in the {@link //ocs. ocs} application.
%%%
-module(ocs_rest_res_product).
-copyright('Copyright (c) 2016 - 2017 SigScale Global Inc.').

-export([content_types_accepted/0, content_types_provided/0]).

-export([add_product_offering/1, add_product_inventory/1]).
-export([get_product_offering/1, get_product_offerings/2]).
-export([on_patch_product_offering/3, merge_patch_product_offering/3]).
-export([get_catalog/2, get_catalogs/1]).
-export([get_category/2, get_categories/1]).
-export([get_product_spec/2, get_product_specs/1]).

-include_lib("radius/include/radius.hrl").
-include("ocs.hrl").

-spec content_types_accepted() -> ContentTypes
	when
		ContentTypes :: list().
%% @doc Provides list of resource representations accepted.
content_types_accepted() ->
	["application/json", "application/json-patch+json",
	"application/merge-patch+json"].

-spec content_types_provided() -> ContentTypes
	when
		ContentTypes :: list().
%% @doc Provides list of resource representations available.
content_types_provided() ->
	["application/json"].

-spec add_product_offering(ReqData) -> Result when
	ReqData	:: [tuple()],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 500 .
%% @doc Respond to `POST /catalogManagement/v2/productOffering'.
%% 	Add a new Product Offering.
add_product_offering(ReqData) ->
	try
		{struct, ObjectMembers} = mochijson:decode(ReqData),
		Name = prod_name(ObjectMembers),
		IsBundle = prod_isBundle(ObjectMembers),
		Status = prod_status(ObjectMembers),
		{StartDate, EndDate} = prod_vf(ObjectMembers),
		Description = prod_description(ObjectMembers),
		case product_offering_price(ObjectMembers) of
			{error, StatusCode} ->
				{error, StatusCode};
			Price ->
				Product = #product{price = Price,
						name = Name, description = Description,
						is_bundle = IsBundle, status = Status,
						start_date = StartDate, end_date = EndDate},
				case ocs:add_product(Product) of
					{ok, LM} ->
						add_product_offering1(Name, LM, ObjectMembers);
					{error, Reason} ->
						{error, Reason}
				end
		end
	catch
		_:_ ->
			{error, 400}
	end.
%% @hidden
add_product_offering1(ProdId, ETag, JsonResponse) ->
	Id = {id, ProdId},
	Json = {struct, [Id | JsonResponse]},
	Body = mochijson:encode(Json),
	Location = "/catalogManagement/v2/productuOffering/" ++ ProdId,
	Headers = [{location, Location}, {etag, etag(ETag)}],
	{ok, Headers, Body}.

-spec add_product_inventory(ReqData) -> Result when
	ReqData	:: [tuple()],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 500 .
%% @doc Respond to `POST /productInventoryManagement/v2/product'.
%% 	Add a new instance of a Product Offering subscription.
add_product_inventory(ReqData) ->
	try
		{struct, Object} = mochijson:decode(ReqData),
		Headers = [{content_type, "application/json"}],
		{ok, Headers, []}
	catch
		_:_ ->
			{error, 400}
	end.

-spec get_product_offering(ProdID) -> Result when
	ProdID	:: string(),
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /catalogManagement/v2/productOffering/{id}'.
%% 	Retrieve a Product Offering.
get_product_offering(ProductID) ->
	case ocs:find_product(ProductID) of
		{ok, Product} ->
			get_product_offering1(Product);
		{error, not_found} ->
			{error, 404};
		{error, _} ->
			{error, 500}
	end.
%% @hidden
get_product_offering1(Product) ->
	Etag = etag(Product#product.last_modified),
	ID = prod_id(Product),
	Description = prod_description(Product),
	Href = prod_href(Product),
	ValidFor = prod_vf(Product),
	IsBundle = prod_isBundle(Product),
	Name = prod_name(Product),
	Status = prod_status(Product),
	case product_offering_price(Product) of
		{error, StatusCode} ->
			{error, StatusCode};
		OfferPrice ->
			Json = {struct, [ID, Name, Description, Href, 
				IsBundle, Status, ValidFor, OfferPrice]},
			Body = mochijson:encode(Json),
			Headers = [{content_type, "application/json"}, {etag, Etag}],
			{ok, Headers, Body}
	end.

-spec get_product_offerings(Query, Headers) -> Result when
	Query :: [{Key :: string(), Value :: string()}],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 412 | 500 .
%% @doc Respond to `GET /catalogManagement/v2/productOffering'.
%% 	Retrieve all Product Offerings.
%% @todo Filtering
get_product_offerings(Query, Headers) ->
	case lists:keytake("fields", 1, Query) of
		{value, {_, Filters}, NewQuery} ->
			get_product_offerings1(NewQuery, Filters, Headers);
		false ->
			get_product_offerings1(Query, [], Headers)
	end.
%% @hidden
get_product_offerings1(Query, Filters, Headers) ->
	case {lists:keyfind("if-match", 1, Headers),
			lists:keyfind("if-range", 1, Headers),
			lists:keyfind("range", 1, Headers)} of
		{{"if-match", Etag}, false, {"range", Range}} ->
			case global:whereis_name(Etag) of
				undefined ->
					{error, 412};
				PageServer ->
					case ocs_rest:range(Range) of
						{error, _} ->
							{error, 400};
						{ok, {Start, End}} ->
							query_page(PageServer, Etag, Query, Filters, Start, End)
					end
			end;
		{{"if-match", Etag}, false, false} ->
			case global:whereis_name(Etag) of
				undefined ->
					{error, 412};
				PageServer ->
					query_page(PageServer, Etag, Query, Filters, undefined, undefined)
			end;
		{false, {"if-range", Etag}, {"range", Range}} ->
			case global:whereis_name(Etag) of
				undefined ->
					case ocs_rest:range(Range) of
						{error, _} ->
							{error, 400};
						{ok, {Start, End}} ->
							query_start(Query, Filters, Start, End)
					end;
				PageServer ->
					case ocs_rest:range(Range) of
						{error, _} ->
							{error, 400};
						{ok, {Start, End}} ->
							query_page(PageServer, Etag, Query, Filters, Start, End)
					end
			end;
		{{"if-match", _}, {"if-range", _}, _} ->
			{error, 400};
		{_, {"if-range", _}, false} ->
			{error, 400};
		{false, false, {"range", Range}} ->
			case ocs_rest:range(Range) of
				{error, _} ->
					{error, 400};
				{ok, {Start, End}} ->
					query_start(Query, Filters, Start, End)
			end;
		{false, false, false} ->
			query_start(Query, Filters, undefined, undefined)
	end.

-spec get_catalog(Id, Query) -> Result when
	Id :: string(),
	Query :: [{Key :: string(), Value :: string()}],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /catalogManagement/v2/catalog/{id}'.
%% 	Retrieve a catalog .
get_catalog("1", [] =  _Query) ->
	Headers = [{content_type, "application/json"}],
	Body = mochijson:encode(product_catalog()),
	{ok, Headers, Body};
get_catalog(_Id,  [] = _Query) ->
	{error, 404};
get_catalog(_Id, _Query) ->
	{error, 400}.

-spec get_catalogs(Query) -> Result when
	Query :: [{Key :: string(), Value :: string()}],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /catalogManagement/v2/catalog'.
%% 	Retrieve all catalogs .
get_catalogs([] =  _Query) ->
	Headers = [{content_type, "application/json"}],
	Object = {array, [product_catalog()]},
	Body = mochijson:encode(Object),
	{ok, Headers, Body};
get_catalogs(_Query) ->
	{error, 400}.

-spec get_category(Id, Query) -> Result when
	Id :: string(),
	Query :: [{Key :: string(), Value :: string()}],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /catalogManagement/v2/category/{id}'.
%% 	Retrieve a category.
get_category("1", [] =  _Query) ->
	Headers = [{content_type, "application/json"}],
	Body = mochijson:encode(prepaid_category()),
	{ok, Headers, Body};
get_category(_Id,  [] = _Query) ->
	{error, 404};
get_category(_Id, _Query) ->
	{error, 400}.

-spec get_categories(Query) -> Result when
	Query :: [{Key :: string(), Value :: string()}],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /catalogManagement/v2/catalog'.
%% 	Retrieve all catalogs .
get_categories([] =  _Query) ->
	Headers = [{content_type, "application/json"}],
	Object = {array, [prepaid_category()]},
	Body = mochijson:encode(Object),
	{ok, Headers, Body};
get_categories(_Query) ->
	{error, 400}.

-spec get_product_spec(Id, Query) -> Result when
	Id :: string(),
	Query :: [{Key :: string(), Value :: string()}],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /catalogManegment/v2/productSpecification/{id}'.
%% 	Retrieve a product specification.
get_product_spec("1", [] = _Query) ->
	Headers = [{content_type, "application/json"}],
	Body = mochijson:encode(spec_product_network()),
	{ok, Headers, Body};
get_product_spec("2", [] = _Query) ->
	Headers = [{content_type, "application/json"}],
	Body = mochijson:encode(spec_product_fixed_quantity_pkg()),
	{ok, Headers, Body};
get_product_spec("3", [] = _Query) ->
	Headers = [{content_type, "application/json"}],
	Body = mochijson:encode(spec_product_rate_plane()),
	{ok, Headers, Body};
get_product_spec("4", [] = _Query) ->
	Headers = [{content_type, "application/json"}],
	Body = mochijson:encode(spec_product_wlan()),
	{ok, Headers, Body};
get_product_spec(_Id, [] = _Query) ->
	{error, 404};
get_product_spec(_Id, _Query) ->
	{error, 400}.

-spec get_product_specs(Query) -> Result when
	Query :: [{Key :: string(), Value :: string()}],
	Result	:: {ok, Headers, Body} | {error, Status},
	Headers	:: [tuple()],
	Body		:: iolist(),
	Status	:: 400 | 404 | 500 .
%% @doc Respond to `GET /catalogManegment/v2/productSpecification'.
%% 	Retrieve all product specifications.
get_product_specs([] = _Query) ->
	Headers = [{content_type, "application/json"}],
	Object = {array, [spec_product_network(),
					spec_product_fixed_quantity_pkg(),
					spec_product_rate_plane(),
					spec_product_wlan()]},
	Body = mochijson:encode(Object),
	{ok, Headers, Body};
get_product_specs(_Query) ->
	{error, 400}.

-spec on_patch_product_offering(ProdId, Etag, ReqData) -> Result
	when
		ProdId	:: string(),
		Etag		:: undefined | list(),
		ReqData	:: [tuple()],
		Result	:: {ok, Headers, Body} | {error, Status},
		Headers	:: [tuple()],
		Body		:: iolist(),
		Status	:: 400 | 500 .
%% @doc Respond to `PATCH /catalogManagement/v2/productOffering/{id}'.
%% 	Update a Product Offering using JSON patch method
%% 	<a href="http://tools.ietf.org/html/rfc6902">RFC6902</a>.
on_patch_product_offering(ProdId, Etag, ReqData) ->
	try
		{array, OpList} = mochijson:decode(ReqData),
		case exe_jsonpatch_ON(ProdId, Etag, OpList) of
			{error, StatusCode} ->
				{error, StatusCode};
			{ok, Product} ->
				NewEtag = etag(Product#product.last_modified),
				ID = prod_id(Product),
				Href = prod_href(Product),
				Name = prod_name(Product),
				Description = prod_description(Product),
				ValidFor = prod_vf(Product),
				IsBundle = prod_isBundle(Product),
				Status = prod_status(Product),
				case product_offering_price(Product) of
					{error, StatusCode} ->
						{error, StatusCode};
					OfferPrice ->
						Json = {struct, [ID, Href, Name, Description,
								ValidFor, IsBundle, Status, OfferPrice]},
						Body = mochijson:encode(Json),
						Headers = [{content_type, "application/json"}, {etag, NewEtag}],
						{ok, Headers, Body}
				end
		end
	catch
		_:_ ->
			{error, 400}
	end.

-spec merge_patch_product_offering(ProdId, Etag, ReqData) -> Result
	when
		ProdId	:: string(),
		Etag		:: undefined | list(),
		ReqData	:: [tuple()],
		Result	:: {ok, Headers, Body} | {error, Status},
		Headers	:: [tuple()],
		Body		:: iolist(),
		Status	:: 400 | 500 .
%% @doc Respond to `PATCH /catalogManagement/v2/productOffering/{id}'.
%% 	Update a Product Offering using merge patch method
%% 	<a href="http://tools.ietf.org/html/rfc7386">RFC7386</a>.
merge_patch_product_offering(ProdId, Etag, ReqData) ->
	try
		Json = mochijson:decode(ReqData),
		case exe_jsonpatch_merge(ProdId, Etag, Json) of
			{error, Reason} ->
				{error, Reason};
			{ok, Response, LM} ->
				Etag = etag(LM),
				Body = mochijson:encode(Response),
				Headers = [{content_type, "application/json"}, {etag, Etag}],
				{ok, Headers, Body}
		end
	catch
		_:_ ->
			{error, 400}
	end.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------
%% @hidden
product_catalog() ->
	Id = {"id", "1"},
	Href = {"href", "/catalogManagement/v2/catalog/1"},
	Type = {"type", "Product Catalog"},
	Name = {"name", "SigScale OCS"},
	Status = {"lifecycleStatus", "Active"},
	Version = {"version", "1.0"},
	LastUpdate = {"lastUpdate", "2017-10-04T00:00:00Z"},
	Category = {"category", {array, [prepaid_category()]}},
	{struct, [Id, Href, Type, Name, Status, Version, LastUpdate, Category]}.

%% @hidden
prepaid_category() ->
	Id = {"id", "1"},
	Href = {"href", "/catalogManagement/v2/category/1"},
	Name = {"name", "Prepaid"},
	Description = {"description", "Services provided with realtime credit management"},
	Version = {"version", "1.0"},
	LastUpdate = {"lastUpdate", "2017-10-04T00:00:00Z"},
	Status = {"lifecycleStatus", "Active"},
	IsRoot = {"isRoot", true},
	{struct, [Id, Href, Name, Description, Version, Status, LastUpdate, IsRoot]}.

%% @hidden
spec_product_network() ->
	Id = {"id", "1"},
	Href = {"href", "/catalogManagement/v2/productSpecification/1"},
	Name = {"name", "NetworkProductSpec"},
	Description = {"description", "Represents the common behaviour and description of an installed network product that will be provisioned in the network and that enables usages."},
	Version = {"version", "1.0"},
	LastUpdate = {"lastUpdate", "2017-10-06T12:00:00Z"},
	Status = {"lifecycleStatus", "Active"},
	{struct, [Id, Name, Href, Description, Version, LastUpdate, Status]}.

%% @hidden
spec_product_fixed_quantity_pkg() ->
	Id = {"id", "2"},
	Href = {"href", "/catalogManagement/v2/productSpecification/2"},
	Name = {"name", "FixedQuantityPackageProductSpec"},
	Description = {"description", "Defines buckets of usage from which Usages will debit the bucket."},
	Version = {"version", "1.0"},
	LastUpdate = {"lastUpdate", "2017-10-06T12:00:00Z"},
	Status = {"lifecycleStatus", "Active"},
	{struct, [Id, Name, Href, Description, Version, LastUpdate, Status]}.

%% @hidden
spec_product_rate_plane() ->
	Id = {"id", "3"},
	Href = {"href", "/catalogManagement/v2/productSpecification/3"},
	Name = {"name", "RatedPlanProductSpec"},
	Description = {"description", "Defines criteria to be used to gain special usage tariffs like the period (day, evening) or phone number."},
	Version = {"version", "1.0"},
	LastUpdate = {"lastUpdate", "2017-10-06T12:00:00Z"},
	Status = {"lifecycleStatus", "Active"},
	{struct, [Id, Name, Href, Description, Version, LastUpdate, Status]}.

%% @hidden
spec_product_wlan() ->
	Id = {"id", "4"},
	Href = {"href", "/catalogManagement/v2/productSpecification/4"},
	Name = {"name", "WLANProductSpec"},
	Description = {"description", "Defines characteristics specific to pulic Wi-Fi use."},
	Version = {"version", "1.0"},
	LastUpdate = {"lastUpdate", "2017-10-06T12:00:00Z"},
	Status = {"lifecycleStatus", "Active"},
	DepType = {"type", "dependency"},
	DepId = {"id", "1"},
	DepHref = {"href", "productCatalogManagement/productSpecification/1"},
	Depend = {struct, [DepId, DepHref, DepType]},
	Dependency = {"productSpecificationRelationship", {array, [Depend]}},
	Chars = {"productSpecCharacteristic", {array, characteristic_product_wlan()}},
	{struct, [Id, Name, Href, Description, Version, LastUpdate, Status, Chars, Dependency]}.

%% @hidden
characteristic_product_wlan() ->
	Name1 = {"name", "subscriberIdentity"},
	Description1 = {"description",
			"Uniquely identifies subscriber (e.g. MSISDN, IMSI, username)."},
	Type1 = {"valueType", "string"},
	Value1 = {"productSpecCharacteristicValue", {array, [{struct, [Type1]}]}},
	Char1 = {struct, [Name1, Description1, Type1, Value1]},
	Name2 = {"name", "subscriberPassword"},
	Description2 = {"description", "Shared secret used in authentication."},
	Type2 = {"valueType", "string"},
	Value2 = {"productSpecCharacteristicValue", {array, [{struct, [Type2]}]}},
	Char2 = {struct, [Name2, Description2, Type2, Value2]},
	Name3 = {"name", "topUpDuration"},
	Description3 = {"description", "Validity period of each top up."},
	Type3 = {"valueType", "integer"},
	Value3 = {"productSpecCharacteristicValue", {array, [{struct, [Type2]}]}},
	Char3 = {struct, [Name3, Description3, Type3, Value3]},
	[Char1, Char2, Char3].

-spec product_offering_price(Product) -> Result
	when
		Product	:: [tuple()] | #product{},
		Result	:: [#price{}] | [tuple()] | {error, Status},
		Status	:: 400.
%% @doc Encode/decode product offering price.
%% @private
product_offering_price([]) ->
	{error, 400};
product_offering_price(ObjectMembers) when is_list(ObjectMembers) ->
	{_, {array, ProductOfferPrice}} = lists:keyfind("productOfferingPrice",
			1, ObjectMembers),
	case product_offering_price(ProductOfferPrice, []) of
		{error, Status} ->
			{error, Status};
		Prices ->
			Prices
	end;
product_offering_price(#product{} = Product) ->
	case product_offering_price(Product#product.price, []) of
		{error, Status} ->
			{error, Status};
		ProductOfferPrice ->
			{"productOfferingPrice", {array, ProductOfferPrice}}
	end.

-spec product_offering_price(ProductOfPrice, Prices) -> Result
	when
		ProductOfPrice	:: [tuple()] | [#price{}],
		Prices	::	list(),
		Result	:: [#price{}] | [tuple()] | {error, Status},
		Status	:: 400 | 500.
%% @hidden
product_offering_price([], Prices) ->
	Prices;
product_offering_price([{struct, ObjectMembers} | T], Prices) ->
	try
		ProdName = prod_price_name(ObjectMembers),
		ProdDescription = prod_price_description(ObjectMembers),
		{StartDate, EndDate} = valid_for(ObjectMembers),
		ProdPriceType = prod_price_type(ObjectMembers),
		{_, {struct, ProdPriceObj}} = lists:keyfind("price", 1, ObjectMembers),
		ProdAmount = prod_price_price_amount(ProdPriceObj),
		CurrencyCode = prod_price_price_c_code(ProdPriceObj),
		RCPeriod = prod_price_rc_period(ObjectMembers),
		{ProdUnits, ProdSize} = prod_price_ufm(ObjectMembers),
		Size = product_size(ProdUnits, octets, ProdSize),
		Price1 = #price{name = ProdName, description = ProdDescription,
				start_date = StartDate, end_date = EndDate,
				type = ProdPriceType, units = ProdUnits, size = Size,
				currency = CurrencyCode, period = RCPeriod, amount = ProdAmount},
		case lists:keyfind("productOfferPriceAlteration", 1, ObjectMembers) of
			false ->
				product_offering_price(T, [Price1 | Prices]);
			{_, {struct, ProdAlterObj}} ->
				case po_alteration(ProdAlterObj) of
					{error, Status} ->
						{error, Status};
					Alteration ->
						Price2 = Price1#price{alteration = Alteration},
						product_offering_price(T, [Price2 | Prices])
				end
		end
	catch
		_:_ ->
			{error, 400}
	end;
product_offering_price([#price{} = Price | T], Prices) ->
	try
		Name = prod_price_name(Price),
		ValidFor = valid_for(Price),
		PriceType = prod_price_type(Price),
		Amount = prod_price_price_amount(Price),
		CurrencyCode = prod_price_price_c_code(Price),
		PriceObj = {"price", {struct, [Amount, CurrencyCode]}},
		RCPeriod = prod_price_rc_period(Price),
		Description = prod_price_description(Price),
		UOMeasure = prod_price_ufm(Price),
		if
			Price#price.alteration == undefined ->
				Price1 = {struct, [Name, Description, ValidFor,
					PriceType, PriceObj, UOMeasure, RCPeriod]},
				product_offering_price(T, [Price1 | Prices]);
			true ->
				case po_alteration(Price#price.alteration) of
					{error, Status} ->
						{error, Status};
					Alteration ->
						Price1 = {struct, [Name, Description, PriceType,
							ValidFor, PriceObj, UOMeasure, RCPeriod, Alteration]},
						product_offering_price(T, [Price1 | Prices])
				end
		end
	catch
		_:_ ->
			{error, 500}
	end.

-spec po_alteration(Alteration) -> Result
	when
		Alteration :: [tuple()] | #alteration{},
		Result	  :: #alteration{} | {error, Status},
		Status	  :: 400 | 500.
%% @private
po_alteration(Alteration) when is_list(Alteration) ->
	try
		Name = prod_price_alter_name(Alteration),
		Description = prod_price_alter_description(Alteration),
		{StartDate, EndDate} = valid_for(Alteration),
		PriceType = prod_price_alter_price_type(Alteration),
		{_, {struct, Price}} = lists:keyfind("price", 1, Alteration),
		Amount = prod_price_alter_amount(Price),
		{Units, UnitSize} = prod_price_alter_ufm(Alteration),
		Size = product_size(Units, octets, UnitSize),
		#alteration{name = Name, description = Description,
			start_date = StartDate, end_date = EndDate,
			type = PriceType, units = Units,
			size = Size, amount = Amount}
	catch
		_:_ ->
			{error, 400}
	end;
po_alteration(#alteration{} = Alteration) ->
	try
		Name = prod_price_alter_name(Alteration),
		Description = prod_price_alter_description(Alteration),
		ValidFor = valid_for(Alteration),
		PriceType = prod_price_alter_price_type(Alteration),
		UFM  = prod_price_alter_ufm(Alteration),
		Amount = prod_price_alter_amount(Alteration),
		Price = {"price", {struct, [Amount]}},
		{"productOfferPriceAlteration",
				{struct, [Name, Description, PriceType, ValidFor, UFM, Price]}}
	catch
		_:_ ->
			{error, 500}
	end.

-spec prod_id(Product) -> Result
	when
		Product	:: [tuple()] | #product{},
		Result	:: string() | tuple().
%% @private
prod_id(#product{} = Product) ->
	{"id", Product#product.name}.

-spec prod_name(Product) -> Result
	when
		Product	:: [tuple()] | #product{},
		Result	:: string() | tuple().
%% @private
prod_name(Product) when is_list(Product) ->
	{_, Name} = lists:keyfind("name", 1, Product),
	Name;
prod_name(#product{} = Product) ->
	{"name", Product#product.name}.

-spec prod_description(Product) -> Result
	when
		Product	:: list() | #product{},
		Result	:: undefined | string() | tuple().
%% @private
prod_description(Product) when is_list(Product) ->
	proplists:get_value("description", Product, undefined);
prod_description(#product{} = Product) ->
	case Product#product.description of
		undefined ->
			{"description", ""};
		Des ->
			{"description", Des}
	end.

-spec prod_href(Product) -> Result
	when
		Product	:: [tuple()] | #product{},
		Result	:: undefined | string() | tuple().
%% @private
prod_href(#product{} = Product) ->
	{"href", "/product/product/" ++ Product#product.name}.

-spec prod_isBundle(Product) -> Result
	when
		Product	:: [tuple()] | #product{},
		Result	:: boolean() | tuple().
%% @private
prod_isBundle(Product) when is_list(Product) ->
	case lists:keyfind("isBundle", 1, Product) of
		{"isBundle", "true"} -> true;
		{"isBundle", true} -> true;
		_ -> false
	end;
prod_isBundle(#product{} = Product) ->
	case Product#product.is_bundle of
		undefined ->
			{"isBundle", ""};
		IsBundle ->
			{"isBundle", IsBundle}
	end.

-spec prod_status(Product) -> Result
	when
		Product	:: [tuple()] | #product{},
		Result	:: string() | tuple().
%% @private
prod_status(Product) when is_list(Product) ->
	case lists:keyfind("lifecycleStatus", 1, Product) of
		{_, FindStatus} ->
			product_status(FindStatus);
		false ->
			undefined
	end;
prod_status(#product{} = Product) ->
	case Product#product.status of
		undefined ->
			{"lifecycleStatus", ""};
		Status ->
			{"lifecycleStatus", Status}
	end.

-spec prod_vf(Product) -> Result
	when
		Product :: [tuple()] | #product{},
		Result :: tuple().
%% @private
prod_vf(Product) when is_list(Product) ->
	case lists:keyfind("validFor", 1, Product) of
		{_, {struct, VFObj}} ->
			case {proplists:get_value("startDateTime", VFObj), proplists:get_value("endDateTime", VFObj)} of
				{undefined, undefined} ->
					{undefined, undefined};
				{undefined, EDT} ->
					{undefined, ocs_rest:iso8601(EDT)};
				{SDT, undefined} ->
					{ocs_rest:iso8601(SDT), undefined};
				{SDT, EDT} ->
					{ocs_rest:iso8601(SDT), ocs_rest:iso8601(EDT)}
			end;
		false ->
			{undefined, undefined}
	end;
prod_vf(#product{} = Product) ->
	case {Product#product.start_date, Product#product.end_date} of
		{undefined, undefined} ->
			{"validFor", {struct, []}};
		{SDateTime, undefined} ->
			SDT = {"startDateTime", ocs_rest:iso8601(SDateTime)},
			{"validFor", {struct, [SDT]}};
		{undefined, EDateTime} ->
			EDT = {"endDateTime", ocs_rest:iso8601(EDateTime)},
			{"validFor", {struct, [EDT]}};
		{SDateTime, EDateTime} ->
			SDT = {"startDateTime", ocs_rest:iso8601(SDateTime)},
			EDT = {"endDateTime", ocs_rest:iso8601(EDateTime)},
			{"validFor", {struct, [SDT, EDT]}}
	end.

-spec prod_price_name(Price) -> Result
	when
		Price :: [tuple()] | #price{},
		Result	:: string() | tuple().
%% @private
prod_price_name(Price) when is_list(Price) ->
	{_, Name} = lists:keyfind("name", 1, Price),
	Name;
prod_price_name(#price{} = Price) ->
	{"name", Price#price.name}.

-spec prod_price_description(Price) -> Result
	when
		Price :: [tuple()] | #price{},
		Result	:: undefined | string() | tuple().
%% @private
prod_price_description(Price) when is_list(Price) ->
	proplists:get_value("description", Price, undefined);
prod_price_description(#price{} = Price) ->
	case Price#price.description of
		undefined ->
			{"description", ""};
		Des ->
			{"description", Des}
	end.

-spec valid_for(P) -> Result
	when
		P      :: [tuple()] | #price{} | #alteration{},
		Result :: tuple().
%% @private
valid_for(P) when is_list(P) ->
	case lists:keyfind("validFor", 1, P) of
		{_,  {struct, VFObj}} ->
			case {proplists:get_value("startDateTime", VFObj), proplists:get_value("endDateTime", VFObj)} of
				{undefined, undefined} ->
					{undefined, undefined};
				{undefined, EDT} ->
					{undefined, ocs_rest:iso8601(EDT)};
				{SDT, undefined} ->
					{ocs_rest:iso8601(SDT), undefined};
				{SDT, EDT} ->
					{ocs_rest:iso8601(SDT), ocs_rest:iso8601(EDT)}
			end;
		false ->
			{undefined, undefined}
	end;
valid_for(#price{start_date = undefined, end_date = undefined}) ->
	{"validFor",{struct, []}};
valid_for(#price{start_date = undefined, end_date = EndDateTime}) ->
	EDT = {"endDateTime", ocs_rest:iso8601(EndDateTime)},
	{"validFor",{struct, [EDT]}};
valid_for(#price{start_date = StartDateTime, end_date = undefined}) ->
	SDT = {"startDateTime", ocs_rest:iso8601(StartDateTime)},
	{"validFor",{struct, [SDT]}};
valid_for(#price{start_date = StartDateTime, end_date = EndDateTime}) ->
	SDT = {"startDateTime", ocs_rest:iso8601(StartDateTime)},
	EDT = {"endDateTime", ocs_rest:iso8601(EndDateTime)},
	{"validFor", {struct, [SDT, EDT]}};
valid_for(#alteration{start_date = undefined, end_date = undefined}) ->
	{"validFor",{struct, []}};
valid_for(#alteration{start_date = undefined, end_date = EndDateTime}) ->
	EDT = {"endDateTime", ocs_rest:iso8601(EndDateTime)},
	{"validFor",{struct, [EDT]}};
valid_for(#alteration{start_date = StartDateTime, end_date = undefined}) ->
	SDT = {"startDateTime", ocs_rest:iso8601(StartDateTime)},
	{"validFor",{struct, [SDT]}};
valid_for(#alteration{start_date = StartDateTime, end_date = EndDateTime}) ->
	SDT = {"startDateTime", ocs_rest:iso8601(StartDateTime)},
	EDT = {"endDateTime", ocs_rest:iso8601(EndDateTime)},
	{"validFor", {struct, [SDT, EDT]}}.

-spec prod_price_type(Price) -> Result
	when
		Price :: [tuple()] | #price{},
		Result	:: atom() | tuple().
%% @private
prod_price_type(Price) when is_list(Price) ->
	{_, ProdPriceTypeS} = lists:keyfind("priceType", 1, Price),
	price_type(ProdPriceTypeS);
prod_price_type(#price{} = Price) ->
	PPT = price_type(Price#price.type),
	{"priceType", PPT}.

-spec prod_price_price_amount(Price) -> Result
	when
		Price		:: [tuple()] | #price{},
		Result	:: integer() | tuple().
%% @private
prod_price_price_amount(Price) when is_list(Price)->
	{_, ProdAmount} = lists:keyfind("taxIncludedAmount", 1, Price),
	ProdAmount;
prod_price_price_amount(#price{} = Price) ->
	case Price#price.amount of
		undefined ->
			{"taxIncludedAmount", ""};
		Amount ->
			{"taxIncludedAmount", Amount}
	end.

-spec prod_price_price_c_code(Price) -> Result
	when
		Price		:: [tuple()] | #price{},
		Result	:: string() | tuple().
%% @private
prod_price_price_c_code(Price) when is_list(Price) ->
	case lists:keyfind("currencyCode", 1, Price) of
		{_, CurrencyCode} ->
			CurrencyCode;
		false ->
			undefined
	end;
prod_price_price_c_code(#price{} = Price) ->
	{"currencyCode", Price#price.currency}.

-spec prod_price_rc_period(Price) -> Result
	when
		Price		:: [tuple()] | #price{},
		Result	:: undefined | string() | tuple().
%% @private
prod_price_rc_period(Price) when is_list(Price) ->
	case lists:keyfind("recurringChargePeriod", 1, Price) of
		{_, RCPeriod} ->
			price_period(RCPeriod);
		false ->
			undefined
	end;
prod_price_rc_period(#price{} = Price) ->
	case Price#price.period of
		undefined ->
			{"recurringChargePeriod", ""};
		RCPeriod ->
			{"recurringChargePeriod", price_period(RCPeriod)}
	end.

-spec prod_price_alter_name(Alteration) -> Result
	when
		Alteration :: [tuple()] | #alteration{},
		Result :: string() | tuple().
%% @private
prod_price_alter_name(Alteration) when is_list(Alteration) ->
	{_, Name} = lists:keyfind("name", 1, Alteration),
	Name;
prod_price_alter_name(#alteration{} = Alteration) ->
	{"name", Alteration#alteration.name}.

-spec prod_price_alter_description(Alteration) -> Result
	when
		Alteration :: list() | #alteration{},
		Result :: undefined | string() | tuple().
%% @private
prod_price_alter_description(Alteration) when is_list(Alteration) ->
	proplists:get_value("description", Alteration, undefined);
prod_price_alter_description(#alteration{} = Alteration) ->
	case Alteration#alteration.description of
		undefined ->
			{"description", ""};
		Des ->
			{"description", Des}
	end.

-spec prod_price_alter_price_type(Alteration) -> Result
	when
		Alteration :: [tuple()] | #alteration{},
		Result     :: undefined | atom().
%% @private
prod_price_alter_price_type(Alteration) when is_list(Alteration) ->
	case lists:keyfind("priceType", 1, Alteration) of
		{_, PriceType} ->
			price_type(PriceType);
		false ->
			undefined
	end;
prod_price_alter_price_type(#alteration{} = Alteration) ->
	case Alteration#alteration.type of
		undefined ->
			{"priceType", ""};
		PT ->
			{"priceType", price_type(PT)}
	end.

-spec prod_price_alter_amount(Alteration) -> Result
	when
		Alteration :: [tuple()] | #alteration{},
		Result     :: undefined | integer() | tuple().
%% @private
prod_price_alter_amount(Alteration) when is_list(Alteration) ->
	{_, PAlterAmount} = lists:keyfind("taxIncludedAmount", 1,  Alteration),
	PAlterAmount;
prod_price_alter_amount(#alteration{} = Alteration) ->
	case Alteration#alteration.amount of
		undefined ->
			{"taxIncludedAmount", ""};
		Amount ->
			{"taxIncludedAmount", Amount}
	end.

-spec prod_price_ufm(Price) -> Result
	when
		Price		:: [tuple()] | #price{},
		Result	:: {Units, Size} | string(),
		Units		:: undefined | unit_of_measure(),
		Size		:: undefined | pos_integer().
%% @doc return units type and size of measurement of a product
%% @private
prod_price_ufm(Price) when is_list(Price) ->
	UFM = proplists:get_value("unitOfMeasure", Price, undefined),
	prod_price_ufm_et(UFM);
prod_price_ufm(#price{} = Price) ->
	Size = Price#price.size,
	Units = Price#price.units,
	{"unitOfMeasure", prod_price_ufm_json(Units, Size)}.

-spec prod_price_alter_ufm(Alteration) -> Result
	when
		Alteration :: [tuple()] | #alteration{},
		Result	  :: {Units, Size} | string(),
		Units		  :: undefined | unit_of_measure(),
		Size		  :: undefined | pos_integer().
%% @doc return units type and size of measurement of a alteration
%% @private
prod_price_alter_ufm(Alteration) when is_list(Alteration) ->
	UFM = proplists:get_value("unitOfMeasure", Alteration),
	prod_price_ufm_et(UFM);
prod_price_alter_ufm(#alteration{} = Alteration) ->
	Units = Alteration#alteration.units,
	Size = product_size(octets, Units, Alteration#alteration.size),
	{"unitOfMeasure", prod_price_ufm_json(Units, Size)}.

prod_price_ufm_json(undefined, _) ->
	"";
prod_price_ufm_json(Units, undefined) ->
	Units;
prod_price_ufm_json(Units, Size) when is_number(Size) ->
	prod_price_ufm_json(Units, integer_to_list(Size));
prod_price_ufm_json(octets, Size) when is_list(Size) ->
	Size ++ "b";
prod_price_ufm_json(gb, Size) when is_list(Size) ->
	Size ++ "g";
prod_price_ufm_json(mb, Size) when is_list(Size) ->
	Size ++ "m";
prod_price_ufm_json(cents, Size) when is_list(Size) ->
	Size ++ "c";
prod_price_ufm_json(seconds, Size) when is_list(Size) ->
	Size ++ "s".

prod_price_ufm_et(undefined) ->
	{undefined, undefined};
prod_price_ufm_et(UFM) ->
	LowerUOM = string:to_lower(UFM),
	prod_price_ufm_et1(LowerUOM).
%% @hidden
prod_price_ufm_et1(UFM) ->
	Suffix = "b",
	case lists:suffix(Suffix, UFM) of
		true ->
			[Size] = string:tokens(UFM, Suffix),
			{octets, list_to_integer(Size)};
		false ->
			prod_price_ufm_et2(UFM)
	end.
%% @hidden
prod_price_ufm_et2(UFM) ->
	Suffix = "g",
	case lists:suffix(Suffix, UFM) of
		true ->
			[Size] = string:tokens(UFM, Suffix),
			{gb, list_to_integer(Size)};
		false ->
			prod_price_ufm_et3(UFM)
	end.
%% @hidden
prod_price_ufm_et3(UFM) ->
	Suffix = "m",
	case lists:suffix(Suffix, UFM) of
		true ->
			[Size] = string:tokens(UFM, Suffix),
			{mb, list_to_integer(Size)};
		false ->
			prod_price_ufm_et4(UFM)
	end.
%% @hidden
prod_price_ufm_et4(UFM) ->
	Suffix = "c",
	case lists:suffix(Suffix, UFM) of
		true ->
			[Size] = string:tokens(UFM, Suffix),
			{cents, list_to_integer(Size)};
		false ->
			prod_price_ufm_et5(UFM)
	end.
%% @hidden
prod_price_ufm_et5(UFM) ->
	Suffix = "s",
	case lists:suffix(Suffix, UFM) of
		true ->
			[Size] = string:tokens(UFM, Suffix),
			{seconds, list_to_integer(Size)};
		false ->
			prod_price_ufm_et6(UFM)
	end.
%% @hidden
prod_price_ufm_et6(_UFM) ->
	{undefined, undefined}.

-spec product_size(UnitsFrom, UnitsTo, Size) -> Result
	when
		UnitsFrom	:: undefined | atom(), % gb | mb | second | cents
		UnitsTo		:: octets,
		Size			:: undefined | pos_integer(),
		Result		:: integer().
%% @private
product_size(UnitsFrom, octets, Size) when
		UnitsFrom == undefined; Size == undefined ->
	0;
product_size(gb, octets, Size) -> Size * 1000000000;
product_size(octets, gb, Size) -> Size div 1000000000;
product_size(mb, octets, Size) -> Size * 1000000;
product_size(octets, mb, Size) -> Size div 1000000;
product_size(_, _, Size) -> Size.

-spec offer_status(Status) -> Status
	when
		Status :: offer_status() | string().
%% @doc CODEC for life cycle status of Product instance.
%% @private
offer_status("In Study") -> in_study;
offer_status("In Design") -> in_design;
offer_status("In Test") -> in_test;
offer_status("Active") -> active;
offer_status("Rejected") -> rejected;
offer_status("Launched") -> launched;
offer_status("Retired") -> retired;
offer_status("Obsolete") -> obsolete;
offer_status(in_study) -> "In Study";
offer_status(in_design) -> "In Design";
offer_status(in_test) -> "In Test";
offer_status(active) -> "Active";
offer_status(rejected) -> "Rejected";
offer_status(launched) -> "Launched";
offer_status(retired) -> "Retired".

-spec product_status(Status) -> Status
	when
		Status :: product_status() | string().
%% @doc CODEC for life cycle status of Product Offering.
%% @private
product_status("Created") -> created;
product_status("Pending Active") -> pending_active;
product_status("Aborted") -> aborted;
product_status("Cancelled") -> cancelled;
product_status("Active") -> active;
product_status("Suspended") -> suspended;
product_status("Pending Terminate") -> pending_terminate;
product_status("Terminated") -> terminated;
product_status(created) -> "Created";
product_status(pending_active) -> "Pending Active";
product_status(aborted) -> "Aborted";
product_status(cancelled) -> "Cancelled";
product_status(active) -> "Active";
product_status(suspended) -> "Suspended";
product_status(pending_terminate) -> "Pending Terminate";
product_status(terminated) -> "Terminated".

-spec price_type(Type) -> Type
	when
		Type :: string() | atom().
%% @doc CODEC for Price Type.
%% @private
price_type("usage") -> usage;
price_type("recurring") -> recurring;
price_type("one_time") -> one_time;
price_type(usage) -> "usage";
price_type(recurring) -> "recurring";
price_type(one_time) -> "one_time".

-spec price_period(Period) -> Period
	when
		Period :: string() | atom().
%% @doc CODEC for Recurring Charge Period.
%% @private
price_period(daily) -> "daily";
price_period(weekly) -> "weekly";
price_period(monthly) -> "monthly";
price_period(yearly) -> "yearly";
price_period("daily") -> daily;
price_period("weekly") -> weekly;
price_period("monthly") -> monthly;
price_period("yearly") -> yearly.

-spec exe_jsonpatch_ON(ProductID, Etag, OperationList) -> Result
	when
		ProductID		:: string() | binary(),
		Etag				:: undefined | tuple(),
		OperationList	:: [tuple()],
		Result			:: list() | {error, StatusCode},
		StatusCode		:: 400 | 404 | 422 | 500.
%% @doc execute object notation json patch
exe_jsonpatch_ON(ProdID, Etag, OperationList) ->
	F = fun() ->
			case mnesia:read(product, ProdID, write) of
				[Entry] when
						Entry#product.last_modified == Etag;
						Etag == undefined ->
					case ocs_rest:parse(OperationList) of
						{error, invalid_format} ->
							throw(malfored_request);
						Operations ->
							case lists:foldl(fun do_patch/2, Entry, Operations) of
								{error, Reason} ->
									throw(Reason);
								Updatedentry ->
									mnesia:delete(product, Entry#product.name, write),
									TS = erlang:system_time(milli_seconds),
									N = erlang:unique_integer([positive]),
									LM = {TS, N},
									NewEntry = Updatedentry#product{last_modified = LM},
									ok = mnesia:write(NewEntry),
									NewEntry
							end
					end;
				[#product{}] ->
					throw(precondition_failed);
				[] ->
					throw(not_found)
			end
	end,
	case mnesia:transaction(F) of
		{atomic, Product} ->
			{ok,  Product};
		{aborted, {throw, malfored_request}} ->
			{error, 400};
		{aborted, {throw, not_found}} ->
			{error, 404};
		{aborted, {throw, precondition_failed}} ->
			{error, 412};
		{aborted, {throw, not_implemented}} ->
			{error, 422};
		{aborted, {throw, unprocessable}} ->
			{error, 422};
		{aborted, _Reason} ->
			{error,  500}
	end.

-spec exe_jsonpatch_merge(ProductID, Etag, Patch) -> Result
	when
		ProductID		:: string() | binary(),
		Etag				:: undefined | tuple(),
		Patch				:: term(),
		Result			:: list() | {error, StatusCode},
		StatusCode		:: 400 | 404 | 422 | 500.
%% @doc execute json merge patch
exe_jsonpatch_merge(ProdID, Etag, Patch) ->
	F = fun() ->
			case mnesia:read(product, ProdID, write) of
				[Entry] when
						Entry#product.last_modified == Etag;
						Etag == undefined ->
					case offer(Entry) of
						{error, Status} ->
							throw(Status);
						Target ->
							Patched = ocs_rest:merge_patch(Target, Patch),
							case offer(Patched) of
								{error, SC} ->
									throw(SC);
								Updatedentry ->
									mnesia:delete(product, Entry#product.name, write),
									TS = erlang:system_time(milli_seconds),
									N = erlang:unique_integer([positive]),
									LM = {TS, N},
									NewEntry = Updatedentry#product{last_modified = LM},
									ok = mnesia:write(NewEntry),
									{Patched, LM}
							end
					end;
				[#product{}] ->
					throw(precondition_failed);
				[] ->
					throw(not_found)
			end
	end,
	case mnesia:transaction(F) of
		{atomic, {Product, LM}} ->
			{ok,  Product, LM};
		{aborted, {throw, malfored_request}} ->
			{error, 400};
		{aborted, {throw, not_found}} ->
			{error, 404};
		{aborted, {throw, precondition_failed}} ->
			{error, 412};
		{aborted, {throw, not_implemented}} ->
			{error, 422};
		{aborted, {throw, unprocessable}} ->
			{error, 422};
		{aborted, _Reason} ->
			{error,  500}
	end.

-spec do_patch(Operation, Product) -> Result
	when
		Operation	:: {Op, Path, Value},
		Product		:: #product{},
		Op				:: replace | add | remove | move | copy | test,
		Path			:: list(),
		Value			:: term(),
		Result		:: #product{} | {error, Reason},
		Reason		:: malfored_request | not_implemented | unprocessable.
%% @doc validate operation and paths for product patch reqeust.
do_patch({replace, Path, Value}, Product) ->
	patch_replace(Path, Value, Product);
do_patch(_, _) ->
	{error, not_implemented}.

patch_replace(["name"], Value, Product) when is_list(Value) ->
	Product#product{name = Value};
patch_replace(["description"], Value, Product) when is_list(Value) ->
	Product#product{description = Value};
patch_replace(["isBundle"], Value, Product) when is_boolean(Value) ->
	Product#product{is_bundle = Value};
patch_replace(["validFor", "startDateTime"], Value, Product) when is_list(Value) ->
	Product#product{start_date = ocs_rest:iso8601(Value)};
patch_replace(["validFor", "endDateTime"], Value, Product) when is_list(Value) ->
	Product#product{end_date = ocs_rest:iso8601(Value)};
patch_replace(["validFor"], {struct, Value}, Product) when is_list(Value) ->
	Product1 = case lists:keyfind("startDateTime", 1, Value) of
		{_, SDT} ->
			Product#product{start_date = ocs_rest:iso8601(SDT)};
		false ->
			Product
	end,
	case lists:keyfind("endDateTime", 1, Value) of
		{_, EDT} ->
			Product1#product{end_date = ocs_rest:iso8601(EDT)};
		false ->
			Product1
	end;
patch_replace(["lifecycleStatus"], Value, Product) when is_list(Value) ->
	S = product_status(Value),
	Product#product{status = S};
patch_replace(["productOfferingPrice" | T], Value, Product) ->
	case patch_replace1(prod_price, T, Value, Product#product.price) of
		{error, Reason} ->
			{error, Reason};
		Price ->
			Product#product{price = Price}
	end;
patch_replace(_, _, _) ->
	{error, unprocessable}.
%% @hidden
patch_replace1(prod_price, [], {array, Values}, _) ->
	try
	F = fun({struct, Obj}, Acc) ->
			F5 = fun(F5, [{"taxIncludedAmount", A} | T], Alter) when is_integer(A) ->
							F5(F5, T, Alter#alteration{amount = A});
						(_, [], Alter) ->
							Alter;
						(_, _, _) ->
							throw(malfored_request)
			end,
			F4 = fun(F4, [{"name", V} | T], Alter) when is_list(V) ->
							NAlter = Alter#alteration{name = V},
							F4(F4, T, NAlter);
						(F4, [{"description", V} | T], Alter) when is_list(V) ->
							NAlter = Alter#alteration{description = V},
							F4(F4, T, NAlter);
						(F4, [{"priceType", V} | T], Alter) when is_list(V) ->
							PT = price_type(V),
							NAlter = Alter#alteration{type = PT},
							F4(F4, T, NAlter);
						(F4, [{"price", {struct, V}} | T], Alter) when is_list(V) ->
							NAlter = F5(F5, V, Alter),
							F4(F4, T, NAlter);
						(F4, [{"unitOfMeasure", V} | T], Alter) when is_list(V) ->
							{AU, AS} = prod_price_ufm_et(V),
							S = product_size(AU, octets, AS),
							NAlter = Alter#alteration{units = AU, size = S},
							F4(F4, T, NAlter);
						(_, [], Alter) ->
							Alter;
						(_, _, _) ->
							throw(malfored_request)
			end,
			F3 = fun(F3, [{"currencyCode", C} | T], Price) when is_list(C)->
							F3(F3, T, Price#price{currency = C});
						(F3, [{"taxIncludedAmount", A} | T], Price) when is_integer(A) ->
							F3(F3, T, Price#price{amount = A});
						(_, [], Price) ->
							Price;
						(_, _, _) ->
							throw(malfored_request)
			end,
			F2 = fun(F2, [{"name", V} | T], Price) when is_list(V)->
							F2(F2, T, Price#price{name = V});
						(F2, [{"description", V} | T], Price) when is_list(V) ->
							F2(F2, T, Price#price{description = V});
						(F2, [{"priceType", V} | T], Price) when is_list(V) ->
							PT = price_type(V),
							F2(F2, T, Price#price{type = PT});
						(F2, [{"unitOfMeasure", V} | T], Price) when is_list(V) ->
							{U, S} = prod_price_ufm_et(V),
							UP = Price#price{units = U, size = S},
							F2(F2, T, UP);
						(F2, [{"recurringChargePeriod", V} | T], Price) when is_list(V) ->
							RcPeriod = price_period(V),
							UP = Price#price{period = RcPeriod},
							F2(F2, T, UP);
						(F2, [{"price", {struct, V}} | T], Price) when is_list(V) ->
							UP = F3(F3, V, Price),
							F2(F2, T, UP);
						(F2, [{"productOfferPriceAlteration", {struct, V}} | T], Price) when is_list(V) ->
							Alter = F4(F4, V, #alteration{}),
							F2(F2, T, Price#price{alteration = Alter});
						(_, [], Price) ->
							Price;
						(_, _, _) ->
							throw(malfored_request)
			end,
			[F2(F2, Obj, #price{}) | Acc]
	end,
	lists:foldl(F, [], Values)
	catch
		_:_ ->
			{error, malfored_request}
	end;
patch_replace1(prod_price, [$- | T], Values, Prices) when Prices =/= undefined ->
	try
		{Hlist, [LastElement]} = lists:split(length(Prices) - 1, Prices),
		NewValues = case {Values, T} of
			{{struct, V}, []} ->
				V;
			{V, [T1]} when is_list(V) ->
				[{T1, V}];
			{V, [T1, T2]} when is_list(V) ->
				[{T1, {struct, [{T2, V}]}}];
			{V, [T1, T2, T3]} when is_list(V) ->
				[{T1, {struct, [{T2, [{struct, [{T3, V}]}]}]}}]
		end,
		case patch_replace2(NewValues, LastElement) of
			{error, Reason} ->
				{error, Reason};
			NLastElement ->
				Hlist ++ [NLastElement]
		end
	catch
		_:_ ->
			{error, unprocessable}
	end;
patch_replace1(prod_price, [Index | T], Values, Prices) when is_integer(Index), Prices =/= undefined  ->
	try
	if
		Index > length(Prices) ->
			{error, malfored_request};
		true ->
			{BNth, _} = lists:split(Index, Prices),
			Nth = lists:nth(Index + 1, Prices),
			ANth = lists:nthtail(Index + 1, Prices),
			NewValues = case {Values, T} of
				{{struct, V}, []} ->
					V;
				{V, [T1]} when is_list(V) ->
					[{T1, V}];
				{V, [T1, T2]} when is_list(V) ->
					[{T1, {struct, [{T2, V}]}}];
				{V, [T1, T2, T3]} when is_list(V) ->
					[{T1, {struct, [{T2, [{struct, [{T3, V}]}]}]}}]
			end,
			case patch_replace2(NewValues, Nth) of
				{error, Reason} ->
					{error, Reason};
				NewNth ->
					BNth ++ [NewNth] ++ ANth
			end
	end
	catch
		_:_ ->
			{error, unprocessable}
	end;
patch_replace1(_, _, _, _) ->
	{error, unprocessable}.
%% @hidden
patch_replace2([], Price) when is_record(Price, price) ->
	Price;
patch_replace2([{"name", Value} | T], Price) when is_record(Price, price), is_list(Value) ->
	patch_replace2(T, Price#price{name = Value});
patch_replace2([{"description", Value} | T], Price) when is_record(Price, price), is_list(Value) ->
	patch_replace2(T, Price#price{description = Value});
patch_replace2([{"priceType", Value} | T], Price) when is_record(Price, price), is_list(Value) ->
	PT = price_type(Value),
	patch_replace2(T, Price#price{type = PT});
patch_replace2([{"recurringChargePeriod", Value} | T], Price) when is_record(Price, price), is_list(Value) ->
	RCP = price_period(Value),
	patch_replace2(T, Price#price{period = RCP});
patch_replace2([{"unitOfMeasure", Value} | T], Price) when is_record(Price, price), is_list(Value) ->
	{U, S} = prod_price_ufm_et(Value),
	UPrice = Price#price{units = U, size = S},
	patch_replace2(T, UPrice);
patch_replace2([{"price", {struct, Value}} | T], Price) when is_record(Price, price), is_list(Value) ->
	case patch_replace4(Value, Price) of
		{error, Reason} ->
			{error, Reason};

		UPrice ->
			patch_replace2(T, UPrice)
	end;
patch_replace2([{"productOfferPriceAlteration", {struct, Value}} | T], #price{alteration = Alter} = Price)
		when is_record(Price, price) and is_list(Value) ->
	case patch_replace3(Value, Alter) of
		{error, Reason} ->
			{error, Reason};
		UAlter ->
			patch_replace2(T, Price#price{alteration = UAlter})
	end;
patch_replace2(_, _) ->
	{error, unprocessable}.
%% @hidden
patch_replace3([], Alter) ->
	Alter;
patch_replace3([{"name", Value} | T], Alter) when is_list(Value) ->
	patch_replace3(T, Alter#alteration{name = Value});
patch_replace3([{"description", Value} | T], Alter) when is_list(Value) ->
	patch_replace3(T, Alter#alteration{description = Value});
patch_replace3([{"priceType", Value} | T], Alter) when is_list(Value) ->
	PT = price_type(Value),
	patch_replace3(T, Alter#alteration{type = PT});
patch_replace3([{"unitOfMeasure", Value} | T], Alter) when is_list(Value) ->
	{AU, AS} = prod_price_ufm_et(Value),
	S = product_size(AU, octets, AS),
	UAlter = Alter#alteration{units = AU, size = S},
	patch_replace3(T, UAlter);
patch_replace3([{"price", {struct, Value}} | T], Alter) when is_list(Value) ->
	case patch_replace4(Value, Alter) of
		{error, Reason} ->
			{error, Reason};
		UAlter ->
			patch_replace3(T, UAlter)
	end;
patch_replace3(_, _) ->
	{error, unprocessable}.
%% @hidden
patch_replace4([], PorA) ->
	PorA;
patch_replace4([{"currencyCode", Value} | T], Price) when is_record(Price, price) ->
	patch_replace4(T, Price#price{currency = Value});
patch_replace4([{"taxIncludedAmount", Value} | T], Price) when is_record(Price, price), is_integer(Value) ->
	patch_replace4(T, Price#price{amount = Value});
patch_replace4([{"taxIncludedAmount", Value} | T], Alter) when is_record(Alter, alteration), is_integer(Value) ->
	patch_replace4(T, #alteration{amount = Value});
patch_replace4(_, _) ->
	{error, unprocessable}.

-spec offer(Product) -> Product
	when
		Product :: #product{} | {struct, [tuple()]}.
%% @doc CODEC for Product Offering.
%% @private
offer(#product{} = P) ->
	offer(record_info(fields, product), P, []);
offer({struct, ObjectMembers}) ->
	offer(ObjectMembers, #product{}).
%% @hidden
offer([{"id", _ID} | T], Acc) ->
	offer(T, Acc);
offer([{"href", _URI} | T], Acc) ->
	offer(T, Acc);
offer([{"name", Name} | T], Acc) when is_list(Name) ->
	offer(T, Acc#product{name = Name});
offer([{"description", Description} | T], Acc) when is_list(Description) ->
	offer(T, Acc#product{description = Description});
offer([{"validFor", {struct, L}} | T], Acc) ->
	Acc1 = case lists:keyfind("startDateTime", 1, L) of
		{_, Start} ->
			Acc#product{start_date = ocs_rest:iso8601(Start)};
		undefined ->
			Acc
	end,
	Acc2 = case lists:keyfind("endDateTime", 1, L) of
		{_, End} ->
			Acc1#product{end_date = ocs_rest:iso8601(End)};
		undefined ->
			Acc
	end,
	offer(T, Acc2);
offer([{"is_bundle", Bundle} | T], Acc) ->
	offer(T, Acc#product{is_bundle = Bundle});
offer([{"lifecycleStatus", Status} | T], Acc) ->
	offer(T, Acc#product{status = offer_status(Status)});
offer([{"price", Price} | T], Acc) ->
	offer(T, Acc#product{price = price(Price)});
offer([{"characteristic", Chars} | T], Acc) when is_list(Chars) ->
	offer(T, Acc#product{characteristics = characteristics(Chars)});
offer([{"lastUpdate", Last} | T], Acc) ->
	offer(T, Acc#product{last_modified = ocs_rest:iso8601(Last)}).
%% @hidden
offer([name | T], #product{name = Name} = P, Acc) when is_list(Name) ->
	offer(T, P, [{"name", Name} | Acc]);
offer([description | T], #product{description = Description} = P,
		Acc) when is_list(Description) ->
	offer(T, P, [{"description", Description} | Acc]);
offer([start_date | T], #product{start_date = Start,
		end_date = undefined} = P, Acc) when is_integer(Start) ->
	ValidFor = {struct, [{"startDateTime", ocs_rest:iso8601(Start)}]},
	offer(T, P, [{"validFor", ValidFor} | Acc]);
offer([start_date | T], #product{start_date = undefined,
		end_date = End} = P, Acc) when is_integer(End) ->
	ValidFor = {struct, [{"endDateTime", ocs_rest:iso8601(End)}]},
	offer(T, P, [{"validFor", ValidFor} | Acc]);
offer([start_date | T], #product{start_date = Start,
		end_date = End} = P, Acc) when is_integer(Start), is_integer(End) ->
	ValidFor = {struct, [{"startDateTime", ocs_rest:iso8601(Start)},
			{"endDateTime", ocs_rest:iso8601(End)}]},
	offer(T, P, [{"validFor", ValidFor} | Acc]);
offer([end_date | T], P, Acc) ->
	offer(T, P, Acc);
offer([is_bundle | T], #product{is_bundle = IsBundle} = P, Acc)
		when is_boolean(IsBundle) ->
	offer(T, P, [{"isBunde", IsBundle} | Acc]);
offer([status | T], #product{status = Status} = P, Acc)
		when Status /= undefined ->
	StatusString = offer_status(Status),
	offer(T, P, [{"lifecycleStatus", StatusString} | Acc]);
offer([price | T], #product{price = Price} = P, Acc)
		when is_integer(Price) ->
	offer(T, P, [{"price", price(Price)} | Acc]);
offer([characteristics | T],
		#product{characteristics = Chars} = P, Acc) when is_list(Chars) ->
	offer(T, P, [{"characteristic", characteristics(Chars)} | Acc]);
offer([last_modified | T], #product{last_modified = Last} = P, Acc)
		when is_integer(Last) ->
	offer(T, P, [{"lastUpdate", ocs_rest:iso8601(Last)} | Acc]);
offer([], _P, Acc) ->
	{struct, lists:reverse(Acc)}.

-spec price(Price) -> Price
	when
		Price :: #product{} | {struct, [tuple()]}.
%% @doc CODEC for Product Offering Price.
%% @private
price(#price{} = P) ->
	price(record_info(fields, price), P, []);
price({struct, ObjectMembers}) ->
	price(ObjectMembers, #price{}).
%% @hidden
price([name| T], #price{name = Name} = P, Acc) when is_list(Name) ->
	price(T, P, [{"name", Name} | Acc]);
price([description | T], #price{description = Description} = P, Acc)
		when is_list(Description) ->
	price(T, P, [{"description", Description} | Acc]);
price([start_date | T], #price{start_date = Start,
		end_date = undefined} = P, Acc) when is_integer(Start) ->
	ValidFor = {struct, [{"startDateTime", ocs_rest:iso8601(Start)}]},
	price(T, P, [{"validFor", ValidFor} | Acc]);
price([start_date | T], #price{start_date = undefined,
		end_date = End} = P, Acc) when is_integer(End) ->
	ValidFor = {struct, [{"endDateTime", ocs_rest:iso8601(End)}]},
	price(T, P, [{"validFor", ValidFor} | Acc]);
price([start_date | T], #price{start_date = Start,
		end_date = End} = P, Acc) when is_integer(Start), is_integer(End) ->
	ValidFor = {struct, [{"startDateTime", ocs_rest:iso8601(Start)},
			{"endDateTime", ocs_rest:iso8601(End)}]},
	price(T, P, [{"validFor", ValidFor} | Acc]);
price([end_date | T], P, Acc) ->
	price(T, P, Acc);
price([type | T], #price{type = one_time, units = cents} = P, Acc) ->
	price(T, P, [{"priceType", price_type(one_time)} | Acc]);
price([type | T], #price{type = recurring, period = Period,
		units = cents} = P, Acc) when Period /= undefined ->
	Recurring = [{"priceType", price_type(recurring)},
			{"recurringChargePeriod", price_period(Period)}],
	price(T, P, Recurring ++ Acc);
price([type | T], #price{type = usage, units = octets,
		size = Size} = P, Acc) when is_integer(Size) ->
	UsageType = [{"priceType", price_type(usage)},
			{"unitOfMeasure", integer_to_list(Size) ++ "b"}],
	price(T, P, UsageType ++ Acc);
price([type | T], #price{type = usage, units = seconds,
		size = Size} = P, Acc) when is_integer(Size) ->
	UsageType = [{"priceType", price_type(usage)},
			{"unitOfMeasure", integer_to_list(Size) ++ "s"}],
	price(T, P, UsageType ++ Acc);
price([period | T], P, Acc) ->
	price(T, P, Acc);
price([units | T], P, Acc) ->
	price(T, P, Acc);
price([size | T], P, Acc) ->
	price(T, P, Acc);
price([amount | T], #price{amount = Amount, currency = Currency} = P, Acc)
		when is_integer(Amount), is_list(Currency) ->
	Price = {struct, [{"taxIncludedAmount", integer_to_list(Amount)},
			{"currencyCode", Currency}]},
	price(T, P, [{"price", Price} | Acc]);
price([amount | T], #price{amount = Amount} = P, Acc)
		when is_integer(Amount) ->
	Price = {struct, [{"taxIncludedAmount", integer_to_list(Amount)}]},
	price(T, P, [{"price", Price} | Acc]);
price([currency | T], P, Acc) ->
	price(T, P, Acc);
price([alteration | T], #price{alteration = Alteration} = P, Acc)
		when is_record(Alteration, alteration) ->
	price(T, P, [{"alteration", alteration(Alteration)} | Acc]);
price([], _P, Acc) ->
	{struct, lists:reverse(Acc)}.
%% @hidden
price([{"id", _ID} | T], Acc) ->
	price(T, Acc);
price([{"href", _URI} | T], Acc) ->
	price(T, Acc);
price([{"name", Name} | T], Acc) when is_list(Name) ->
	price(T, Acc#price{name = Name});
price([{"description", Description} | T], Acc) when is_list(Description) ->
	price(T, Acc#price{description = Description});
price([{"validFor", {struct, L}} | T], Acc) ->
	Acc1 = case lists:keyfind("startDateTime", 1, L) of
		{_, Start} ->
			Acc#price{start_date = ocs_rest:iso8601(Start)};
		undefined ->
			Acc
	end,
	Acc2 = case lists:keyfind("endDateTime", 1, L) of
		{_, End} ->
			Acc1#price{end_date = ocs_rest:iso8601(End)};
		undefined ->
			Acc
	end,
	price(T, Acc2);
price([{"priceType", Type} | T], Acc) ->
	price(T, Acc#price{type = price_type(Type)});
price([{"unitOfMeasure", UnitOfMeasure} | T], Acc) ->
	case lists:last(UnitOfMeasure) of
		$b ->
			N = lists:sublist(UnitOfMeasure, length(UnitOfMeasure) - 1),
			price(T, Acc#price{units = octets, size = list_to_integer(N)});
		$s ->
			N = lists:sublist(UnitOfMeasure, length(UnitOfMeasure) - 1),
			price(T, Acc#price{units = seconds, size = list_to_integer(N)});
		_ ->
			price(T, Acc#price{size = list_to_integer(UnitOfMeasure)})
	end;
price([{"price", {struct, L}} | T], Acc) ->
	Acc1 = case lists:keyfind("taxIncludedAmount", 1, L) of
		{_, Amount} when is_integer(Amount) ->
			Acc#price{amount = Amount};
		_ ->
			Acc
	end,
	Acc2 = case lists:keyfind("currency", 1, L) of
		{_, Currency} when is_list(Currency) ->
			Acc1#price{currency = Currency};
		_ ->
			Acc1
	end,
	price(T, Acc2);
price([{"recurringChargePeriod", Period} | T], Acc) ->
	price(T, Acc#price{period = price_period(Period)});
price([{"productOfferPriceAlteration", Alteration} | T], Acc)
		when is_record(Alteration, alteration) ->
	price(T, Acc#price{alteration = alteration(Alteration)});
price([], Acc) ->
	Acc.

-spec alteration(Alteration) -> Alteration
	when
		Alteration :: #alteration{} | {struct, [tuple()]}.
%% @doc CODEC for Product Offering Price Alteration.
%% @private
alteration(#alteration{} = A) ->
	alteration(record_info(fields, alteration), A, []);
alteration({struct, ObjectMembers}) ->
	alteration(ObjectMembers, #alteration{}).
%% @hidden
alteration([name| T], #alteration{name = Name} = A, Acc) when is_list(Name) ->
	alteration(T, A, [{"name", Name} | Acc]);
alteration([description | T], #alteration{description = Description} = A, Acc)
		when is_list(Description) ->
	alteration(T, A, [{"description", Description} | Acc]);
alteration([start_date | T], #alteration{start_date = Start,
		end_date = undefined} = A, Acc) when is_integer(Start) ->
	ValidFor = {struct, [{"startDateTime", ocs_rest:iso8601(Start)}]},
	alteration(T, A, [{"validFor", ValidFor} | Acc]);
alteration([start_date | T], #alteration{start_date = undefined,
		end_date = End} = A, Acc) when is_integer(End) ->
	ValidFor = {struct, [{"endDateTime", ocs_rest:iso8601(End)}]},
	alteration(T, A, [{"validFor", ValidFor} | Acc]);
alteration([start_date | T], #alteration{start_date = Start,
		end_date = End} = A, Acc) when is_integer(Start), is_integer(End) ->
	ValidFor = {struct, [{"startDateTime", ocs_rest:iso8601(Start)},
			{"endDateTime", ocs_rest:iso8601(End)}]},
	alteration(T, A, [{"validFor", ValidFor} | Acc]);
alteration([end_date | T], A, Acc) ->
	alteration(T, A, Acc);
alteration([type | T], #alteration{type = one_time, units = cents} = A, Acc) ->
	alteration(T, A, [{"priceType", price_type(one_time)} | Acc]);
alteration([type | T], #alteration{type = recurring, period = Period,
		units = cents} = A, Acc) when Period /= undefined ->
	Recurring = [{"priceType", price_type(recurring)},
			{"recurringChargePeriod", price_period(Period)}],
	alteration(T, A, Recurring ++ Acc);
alteration([type | T], #alteration{type = usage, units = octets,
		size = Size} = A, Acc) when is_integer(Size) ->
	UsageType = [{"priceType", price_type(usage)},
			{"unitOfMeasure", integer_to_list(Size) ++ "b"}],
	alteration(T, A, UsageType ++ Acc);
alteration([type | T], #alteration{type = usage, units = seconds,
		size = Size} = A, Acc) when is_integer(Size) ->
	UsageType = [{"priceType", price_type(usage)},
			{"unitOfMeasure", integer_to_list(Size) ++ "s"}],
	alteration(T, A, UsageType ++ Acc);
alteration([period | T], A, Acc) ->
	alteration(T, A, Acc);
alteration([units | T], A, Acc) ->
	alteration(T, A, Acc);
alteration([size | T], A, Acc) ->
	alteration(T, A, Acc);
alteration([amount | T], #alteration{amount = Amount, currency = Currency} = A, Acc)
		when is_integer(Amount), is_list(Currency) ->
	Price = {struct, [{"taxIncludedAmount", integer_to_list(Amount)},
			{"currencyCode", Currency}]},
	alteration(T, A, [{"price", Price} | Acc]);
alteration([amount | T], #alteration{amount = Amount} = A, Acc)
		when is_integer(Amount) ->
	Price = {struct, [{"taxIncludedAmount", integer_to_list(Amount)}]},
	alteration(T, A, [{"price", Price} | Acc]);
alteration([currency | T], A, Acc) ->
	alteration(T, A, Acc);
alteration([], _A, Acc) ->
	{struct, lists:reverse(Acc)}.
%% @hidden
alteration([{"id", _ID} | T], Acc) ->
	alteration(T, Acc);
alteration([{"href", _URI} | T], Acc) ->
	alteration(T, Acc);
alteration([{"name", Name} | T], Acc) when is_list(Name) ->
	alteration(T, Acc#alteration{name = Name});
alteration([{"description", Description} | T], Acc) when is_list(Description) ->
	alteration(T, Acc#alteration{description = Description});
alteration([{"validFor", {struct, L}} | T], Acc) ->
	Acc1 = case lists:keyfind("startDateTime", 1, L) of
		{_, Start} ->
			Acc#alteration{start_date = ocs_rest:iso8601(Start)};
		undefined ->
			Acc
	end,
	Acc2 = case lists:keyfind("endDateTime", 1, L) of
		{_, End} ->
			Acc1#alteration{end_date = ocs_rest:iso8601(End)};
		undefined ->
			Acc
	end,
	alteration(T, Acc2);
alteration([{"priceType", Type} | T], Acc) ->
	alteration(T, Acc#alteration{type = price_type(Type)});
alteration([{"unitOfMeasure", UnitOfMeasure} | T], Acc) ->
	case lists:last(UnitOfMeasure) of
		$b ->
			N = lists:sublist(UnitOfMeasure, length(UnitOfMeasure) - 1),
			alteration(T, Acc#alteration{units = octets, size = list_to_integer(N)});
		$s ->
			N = lists:sublist(UnitOfMeasure, length(UnitOfMeasure) - 1),
			alteration(T, Acc#alteration{units = seconds, size = list_to_integer(N)});
		_ ->
			alteration(T, Acc#alteration{size = list_to_integer(UnitOfMeasure)})
	end;
alteration([{"alteration", {struct, L}} | T], Acc) ->
	Acc1 = case lists:keyfind("taxIncludedAmount", 1, L) of
		{_, Amount} when is_integer(Amount) ->
			Acc#alteration{amount = Amount};
		_ ->
			Acc
	end,
	Acc2 = case lists:keyfind("currency", 1, L) of
		{_, Currency} when is_list(Currency) ->
			Acc1#alteration{currency = Currency};
		_ ->
			Acc1
	end,
	alteration(T, Acc2);
alteration([{"recurringChargePeriod", Period} | T], Acc) ->
	alteration(T, Acc#alteration{period = price_period(Period)});
alteration([], Acc) ->
	Acc.

-spec characteristics(Characteristics) -> Characteristics
	when
		Characteristics :: [tuple()].
%% @doc CODEC for Product Specification Characteristics.
%% @private
characteristics([]) -> [].

%% @hidden
query_start(Query, Filters, RangeStart, RangeEnd) ->
	Name =  proplists:get_value("name", Query),
	Des = proplists:get_value("description", Query),
	Status = case lists:keyfind("licecycleStatus", 1, Query) of
		false ->
			undefined;
		{_, S} ->
			product_status(S)
	end,
	SDT = proplists:get_value("startDate", Query),
	EDT = proplists:get_value("endDate", Query),
	Price = proplists:get_value("price", Query),
	case supervisor:start_child(ocs_rest_pagination_sup,
				[[ocs, query_product, [Name, Des, Status, SDT, EDT, Price]]]) of
		{ok, PageServer, Etag} ->
			query_page(PageServer, Etag, Query, Filters, RangeStart, RangeEnd);
		{error, _Reason} ->
			{error, 500}
	end.

query_page(PageServer, Etag, Query, Filters, Start, End) ->
	case gen_server:call(PageServer, {Start, End}) of
		{error, Status} ->
			{error, Status};
		{Events, ContentRange} ->
			try
				case lists:keytake("sort", 1, Query) of
					{value, {_, "name"}, Q1} ->
						{lists:keysort(#product.name, Events), Q1};
					{value, {_, "-name"}, Q1} ->
						{lists:reverse(lists:keysort(#product.name, Events)), Q1};
					{value, {_, "description"}, Q1} ->
						{lists:keysort(#product.description, Events), Q1};
					{value, {_, "-description"}, Q1} ->
						{lists:reverse(lists:keysort(#product.description, Events)), Q1};
					{value, {_, "licecycleStatus"}, Q1} ->
						{lists:keysort(#product.status, Events), Q1};
					{value, {_, "-lifecycleStatus"}, Q1} ->
						{lists:reverse(lists:keysort(#product.status, Events)), Q1};
					{value, {_, "startDate"}, Q1} ->
						{lists:keysort(#product.start_date, Events), Q1};
					{value, {_, "-startDate"}, Q1} ->
						{lists:reverse(lists:keysort(#product.start_date, Events)), Q1};
					{value, {_, "endDate"}, Q1} ->
						{lists:keysort(#product.end_date, Events), Q1};
					{value, {_, "-endDate"}, Q1} ->
						{lists:reverse(lists:keysort(#product.end_date, Events)), Q1};
					{value, {_, "price"}, Q1} ->
						{lists:keysort(#product.price, Events), Q1};
					{value, {_, "-price"}, Q1} ->
						{lists:reverse(lists:keysort(#product.price, Events)), Q1};
					false ->
						{Events, Query};
					_ ->
						throw(400)
				end
			of
				{SortedEvents, _NewQuery} ->
					JsonObj = query_page1(lists:map(fun product_json/1, SortedEvents), Filters, []),
					JsonArray = {array, JsonObj},
					Body = mochijson:encode(JsonArray),
					Headers = [{content_type, "application/json"},
							{etag, Etag}, {accept_ranges, "items"},
							{content_range, ContentRange}],
					{ok, Headers, Body}
			catch
				throw:{error, Status} ->
					{error, Status}
			end
	end.
%% @hidden
query_page1([], _, Acc) ->
	lists:reverse(Acc);
query_page1(Json, [], Acc) ->
	lists:reverse(Json ++ Acc);
query_page1([H | T], Filters, Acc) ->
	query_page1(T, Filters, [ocs_rest:filter(Filters, H) | Acc]).

product_json(#product{} = Product) ->
	ID = prod_id(Product),
	Href = prod_href(Product),
	Name = prod_name(Product),
	Description = prod_description(Product),
	ValidFor = prod_vf(Product),
	IsBundle = prod_isBundle(Product),
	Status = prod_status(Product),
	case product_offering_price(Product) of
		{error, StatusCode} ->
			throw(StatusCode);
		OfferPrice ->
			{struct, [ID, Href, Name, Description,
					ValidFor, IsBundle, Status, OfferPrice]}
	end.

-spec etag(V1) -> V2
	when
		V1 :: string() | {N1, N2},
		V2 :: {N1, N2} | string(),
		N1 :: integer(),
		N2 :: integer().
%% @doc Generate a tuple with 2 integers from Etag string
%% value or vice versa.
%% @hidden
etag(V) when is_list(V) ->
	[TS, N] = string:tokens(V, "-"),
	{list_to_integer(TS), list_to_integer(N)};
etag(V) when is_tuple(V) ->
	{TS, N} = V,
	integer_to_list(TS) ++ "-" ++ integer_to_list(N).

