## Makefile.am
## vim: ts=3
##
## Process this file with automake to produce Makefile.in

appdir = $(beamdir)
app_DATA = ocs.app
EXTRA_DIST = ocs.app

beam_DATA = ocs.beam \
			ocs_app.beam \
			ocs_sup.beam \
			ocs_diameter_auth_port_server.beam \
			ocs_diameter_auth_port_sup.beam \
			ocs_diameter_auth_service_fsm_sup.beam \
			ocs_diameter_acct_service_fsm_sup.beam \
			ocs_diameter_auth_service_fsm.beam \
			ocs_diameter_acct_service_fsm.beam \
			ocs_diameter_auth_sup.beam \
			ocs_diameter_disconnect_fsm_sup.beam\
			ocs_diameter_disconnect_fsm.beam\
			ocs_radius_acct_port_server.beam \
			ocs_radius_acct_port_sup.beam \
			ocs_diameter_acct_port_sup.beam \
			ocs_diameter_acct_top_sup.beam \
			ocs_radius_acct_top_sup.beam \
			ocs_radius_acct_server_sup.beam \
			ocs_radius_auth_server_sup.beam \
			ocs_radius_auth_sup.beam \
			ocs_eap_pwd_fsm_sup.beam \
			ocs_eap_ttls_fsm_sup_sup.beam \
			ocs_eap_ttls_fsm_sup.beam \
			ocs_radius_auth_port_sup.beam \
			ocs_simple_auth_fsm_sup.beam \
			ocs_radius_disconnect_fsm_sup.beam\
			ocs_radius_disconnect_fsm.beam\
			ocs_eap_pwd_fsm.beam \
			ocs_eap_ttls_fsm.beam \
			ocs_eap_ttls_aaah_fsm.beam \
			ocs_eap_aka_fsm_sup_sup.beam \
			ocs_eap_aka_fsm_sup.beam \
			ocs_eap_aka_fsm.beam \
			ocs_eap_akap_fsm_sup_sup.beam \
			ocs_eap_akap_fsm_sup.beam \
			ocs_eap_akap_fsm.beam \
			ocs_eap_aka_auc_fsm.beam \
			ocs_pgw_fsm_sup.beam \
			ocs_pgw_fsm.beam \
			ocs_terminate_fsm_sup.beam \
			ocs_terminate_fsm.beam \
			ocs_deregister_fsm_sup.beam \
			ocs_deregister_fsm.beam \
			ocs_simple_auth_fsm.beam \
			ocs_radius_auth_port_server.beam \
			ocs_radius_accounting.beam \
			ocs_radius_authentication.beam \
			ocs_server.beam \
			ocs_log.beam \
			ocs_gtt.beam \
			ocs_log_rotate_server.beam \
			ocs_eap_codec.beam \
			ocs_eap_pwd.beam \
			ocs_eap_aka.beam \
			ocs_eap_tls_transport.beam \
			ocs_milenage.beam \
			ocs_rating.beam \
			mod_ocs_rest_lang.beam \
			mod_ocs_rest_accepted_content.beam \
			mod_ocs_rest_get.beam \
			mod_ocs_rest_post.beam \
			mod_ocs_rest_patch.beam \
			mod_ocs_rest_delete.beam \
			mod_oauth.beam \
			ocs_rest.beam \
			ocs_rest_res_client.beam \
			ocs_rest_res_usage.beam \
			ocs_rest_res_user.beam \
			ocs_rest_res_balance.beam \
			ocs_rest_res_product.beam \
			ocs_rest_res_service.beam \
			ocs_rest_res_nrf.beam \
			diameter_gen_ietf.beam \
			diameter_gen_etsi.beam \
			diameter_gen_3gpp.beam \
			diameter_gen_3gpp_ro_application.beam \
			ocs_diameter_3gpp_ro_nrf_app_cb.beam \
			diameter_gen_3gpp_sta_application.beam \
			diameter_gen_3gpp_swm_application.beam \
			diameter_gen_3gpp_swx_application.beam \
			diameter_gen_3gpp_s6a_application.beam \
			diameter_gen_3gpp_s6b_application.beam \
			diameter_gen_3gpp_gx_application.beam \
			diameter_gen_nas_application_rfc7155.beam \
			diameter_gen_cc_application_rfc4006.beam \
			diameter_gen_eap_application_rfc4072.beam \
			ocs_diameter_base_application_cb.beam \
			ocs_diameter_nas_application_cb.beam \
			ocs_diameter_eap_application_cb.beam \
			ocs_diameter_cc_application_cb.beam \
			ocs_diameter_3gpp_ro_application_cb.beam \
			ocs_diameter_3gpp_sta_application_cb.beam \
			ocs_diameter_3gpp_swm_application_cb.beam \
			ocs_diameter_3gpp_swx_application_cb.beam \
			ocs_diameter_3gpp_s6a_application_cb.beam \
			ocs_diameter_3gpp_s6b_application_cb.beam \
			ocs_diameter_3gpp_gx_application_cb.beam \
			ocs_diameter_codec_swm.beam \
			ocs_diameter_codec_sta.beam \
			ocs_diameter_codec_s6b.beam \
			ocs_rest_res_http.beam \
			ocs_rest_res_prometheus.beam \
			ocs_rest_res_resource.beam \
			ocs_rest_pagination_sup.beam \
			ocs_rest_pagination_server.beam \
			ocs_scheduler.beam \
			ocs_rest_query_scanner.beam \
			ocs_rest_query_parser.beam \
			ocs_mib.beam \
			ocs_rest_hub_sup.beam \
			ocs_rest_hub_fsm.beam \
			ocs_rest_hub_balance.beam \
			ocs_rest_hub_product.beam \
			ocs_rest_hub_service.beam \
			ocs_rest_hub_user.beam \
			ocs_rest_hub_resource.beam \
			ocs_rest_hub_usage.beam \
			ocs_event.beam

%.beam:$(top_srcdir)/src/%.erl	$(top_srcdir)/include/ocs.hrl \
		$(top_srcdir)/include/ocs_log.hrl \
		$(top_srcdir)/include/ocs_eap_codec.hrl \
		$(top_builddir)/include/diameter_gen_3gpp_ro_application.hrl \
		$(top_builddir)/include/diameter_gen_3gpp_sta_application.hrl \
		$(top_builddir)/include/diameter_gen_3gpp_swm_application.hrl \
		$(top_builddir)/include/diameter_gen_3gpp_swx_application.hrl \
		$(top_builddir)/include/diameter_gen_3gpp_s6a_application.hrl \
		$(top_builddir)/include/diameter_gen_3gpp_s6b_application.hrl \
		$(top_builddir)/include/diameter_gen_3gpp_gx_application.hrl \
		$(top_builddir)/include/diameter_gen_nas_application_rfc7155.hrl \
		$(top_builddir)/include/diameter_gen_cc_application_rfc4006.hrl \
		$(top_builddir)/include/diameter_gen_eap_application_rfc4072.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_srcdir)/include -I $(top_builddir)/include $<

diameter_gen_ietf.beam:$(top_builddir)/src/diameter_gen_ietf.erl \
		$(top_builddir)/include/diameter_gen_ietf.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_etsi.beam:$(top_builddir)/src/diameter_gen_etsi.erl \
		$(top_builddir)/include/diameter_gen_etsi.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_3gpp.beam:$(top_builddir)/src/diameter_gen_3gpp.erl \
		$(top_builddir)/include/diameter_gen_3gpp.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_3gpp_ro_application.beam:$(top_builddir)/src/diameter_gen_3gpp_ro_application.erl \
		$(top_builddir)/include/diameter_gen_3gpp_ro_application.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_3gpp_sta_application.beam:$(top_builddir)/src/diameter_gen_3gpp_sta_application.erl \
		$(top_builddir)/include/diameter_gen_3gpp_sta_application.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_3gpp_swm_application.beam:$(top_builddir)/src/diameter_gen_3gpp_swm_application.erl \
		$(top_builddir)/include/diameter_gen_3gpp_swm_application.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_3gpp_swx_application.beam:$(top_builddir)/src/diameter_gen_3gpp_swx_application.erl \
		$(top_builddir)/include/diameter_gen_3gpp_swx_application.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_3gpp_s6a_application.beam:$(top_builddir)/src/diameter_gen_3gpp_s6a_application.erl \
		$(top_builddir)/include/diameter_gen_3gpp_s6a_application.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_3gpp_s6b_application.beam:$(top_builddir)/src/diameter_gen_3gpp_s6b_application.erl \
		$(top_builddir)/include/diameter_gen_3gpp_s6b_application.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_3gpp_gx_application.beam:$(top_builddir)/src/diameter_gen_3gpp_gx_application.erl \
		$(top_builddir)/include/diameter_gen_3gpp_gx_application.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_nas_application_rfc7155.beam:$(top_builddir)/src/diameter_gen_nas_application_rfc7155.erl \
		$(top_builddir)/include/diameter_gen_nas_application_rfc7155.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_cc_application_rfc4006.beam:$(top_builddir)/src/diameter_gen_cc_application_rfc4006.erl \
		$(top_builddir)/include/diameter_gen_nas_application_rfc7155.hrl \
		$(top_builddir)/include/diameter_gen_cc_application_rfc4006.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_eap_application_rfc4072.beam:$(top_builddir)/src/diameter_gen_eap_application_rfc4072.erl \
		$(top_builddir)/include/diameter_gen_nas_application_rfc7155.hrl \
		$(top_builddir)/include/diameter_gen_eap_application_rfc4072.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

ocs_rest_query_scanner.beam:$(top_builddir)/src/ocs_rest_query_scanner.erl
	$(ERLC) $<

ocs_rest_query_parser.beam:$(top_builddir)/src/ocs_rest_query_parser.erl
	$(ERLC) $<

%.app:   %.app-in
	sed -e 's/%APP_NAME%/$(PACKAGE_NAME)/' \
			-e 's/%APP_VERSION%/$(PACKAGE_VERSION)/' \
			-e 's#%APP_PRIV%#$(ERLANG_INSTALL_LIB_DIR)/$(PACKAGE_NAME)-$(PACKAGE_VERSION)/priv#' < $< > $@ 

CLEANFILES = $(beam_DATA) $(app_DATA)

