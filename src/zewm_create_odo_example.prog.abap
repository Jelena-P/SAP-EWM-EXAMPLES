*&---------------------------------------------------------------------*
*& Report ZEWM_CREATE_ODO_EXAMPLE
*&---------------------------------------------------------------------*
*& Hi there! This is an example of the code that creates an outbound
*& delivery order (ODO) in EWM. This is meant to help with prototyping
*& and not used "as is" in production. This may not work for every
*& scenario and adjustments may be needed. Run through the code and see
*& which part fails, then make adjustments.
*& The code is structured in a way to make it easier to split into
*& the class methods when prototype is successful.
*& This example is open source and free to use. If you have an idea
*& how to improve it, then feel free to contribute. Good luck!
*&---------------------------------------------------------------------*
REPORT zewm_create_odo_example.

* Might want to add default/memory values, otherwis testing is tiresome
PARAMETERS: p_lgnum  TYPE /scwm/lgnum OBLIGATORY,
            p_hu     TYPE /scwm/de_huident OBLIGATORY,
            p_shipto TYPE /scdl/dl_partyno OBLIGATORY,  "Might not be needed
            p_doctyp TYPE /scdl/dl_doctype OBLIGATORY,  "Document Type
            p_itemty TYPE /scdl/dl_itemtype OBLIGATORY. "Item Type

START-OF-SELECTION.

  DATA:
    rejected     TYPE boole_d,
    return_codes TYPE /scdl/t_sp_return_code.

  CONSTANTS:
    BEGIN OF party_roles,
      warehouse       TYPE /scdl/dl_party_role VALUE 'WE'  ##NO_TEXT,
      sales_office    TYPE /scdl/dl_party_role VALUE 'SO'  ##NO_TEXT,
      ship_to_partner TYPE /scdl/dl_party_role VALUE 'STPRT'  ##NO_TEXT,
    END OF party_roles .

  CONSTANTS manual_entry_ind TYPE /scdl/dl_indicator VALUE 'M' ##NO_TEXT.

* I guess message_box declaration could be combined with delivery_sp
* but I find this way is more clear anyway
  DATA(message_box) = NEW /scdl/cl_sp_message_box( ).
  DATA(delivery_sp) = NEW /scdl/cl_sp_prd_out(
    io_message_box = message_box
    iv_doccat      = /scdl/if_dl_doc_c=>sc_doccat_out_prd   " Outbound = PDO
    iv_mode        = /scdl/cl_sp=>sc_mode_classic ).        " No idea what this is for

* Important! This sort of starts LUW
  /scwm/cl_tm=>set_lgnum( p_lgnum ).

* ================================================================================= Header
  DATA headers_out  TYPE /scdl/t_sp_a_head.

  DATA(headers_in) = VALUE /scdl/t_sp_a_head( ( doctype    = p_doctyp
                                                doccat     = /scdl/if_dl_doc_c=>sc_doccat_out_prd "Might nor be needed?
                                                manual     = abap_true ) ).

  delivery_sp->insert( EXPORTING inrecords    = headers_in
                                 aspect       = /scdl/if_sp_c=>sc_asp_head
                       IMPORTING outrecords   = headers_out
                                 rejected     = rejected
                                 return_codes = return_codes ).

* I find that return_codes is mostly useless but it's here just in case. Also,
* messages don't have the actual text like BAPI return table (who designed this?!).
* You'll need to find the message text by ID or add some code to get the text.
* Was too tired to do that, sorry.
  IF rejected = abap_true.
    DATA(messages) = message_box->get_messages_with_no( ).
    cl_demo_output=>display( messages ).
    RETURN.
  ENDIF.

* Could also use "itab not found" exception if feeling fancy
  IF headers_out IS INITIAL.
    MESSAGE 'Empty header returned' TYPE 'E'.
  ENDIF.
  DATA(docid) = headers_out[ 1 ]-docid.

* ================================================================================= Parties
  DATA: headers_partyloc_out TYPE /scdl/t_sp_a_head_partyloc,
        relation_outrecord   TYPE /scdl/s_sp_a_head.
  DATA: warehouse_location TYPE /scwm/s_lgnumlocid.

* I'm not sure what this is for exactly. Found this somewhere on SCN and it solved
* a "warehouse not found" error that was raised otherwise.
  CALL FUNCTION '/SCWM/LGNUM_LOCID_READ'
    EXPORTING
      iv_lgnum       = p_lgnum
    IMPORTING
      es_data        = warehouse_location
    EXCEPTIONS
      data_not_found = 1
      OTHERS         = 2.
  IF sy-subrc <> 0.
    MESSAGE 'Warehouse location not found' TYPE 'E'.
  ENDIF.

* You might need different parties, check your requirements.
  DATA(headers_partyloc_in) = VALUE /scdl/t_sp_a_head_partyloc( docid = docid
                                                                  ( party_role = /scdl/if_dl_partyloc_c=>sc_party_role_wh
                                                                  role_cat   = /scdl/if_dl_partyloc_c=>sc_role_cat_lo
                                                                  locationid = warehouse_location-locid
                                                                    locationno = warehouse_location-locno )
                                                                  ( party_role = party_roles-sales_office
                                                                    orgunitno  = warehouse_location-entity )
                                                                ( party_role = party_roles-ship_to_partner
                                                                  partyno    = p_shipto
                                                                  value_ind  = manual_entry_ind )
                                                                   ).

  DATA(relation_inkey) = VALUE /scdl/s_sp_k_head( docid = docid ).

  delivery_sp->insert( EXPORTING aspect             = /scdl/if_sp_c=>sc_asp_head_partyloc
                                 relation           = /scdl/if_sp_c=>sc_rel_head_to_partyloc
                                 relation_inkey     = relation_inkey
                                 inrecords          = headers_partyloc_in
                       IMPORTING outrecords         = headers_partyloc_out
                                 relation_outrecord = relation_outrecord
                                 rejected           = rejected
                                 return_codes       = return_codes ).

  IF rejected = abap_true.
    messages = message_box->get_messages_with_no( ).
    cl_demo_output=>display( messages ).
    RETURN.
  ENDIF.

* ================================================================================= REFDOC
* Without this part, error /SCWM/DELIVERY  235 is raised  ¯\_(ツ)_/¯

  DATA: headers_refdoc_out TYPE /scdl/t_sp_a_head_refdoc.

  CONSTANTS refdoc_cat_erp TYPE /scdl/dl_refdoccat VALUE 'ERO'.

* Again, no idea what this is for but it's somehow required. The source for
* the "key" seems to be BSKEY field in /scmb/tbussys table if you're curious
  /scwm/cl_mq_services=>get_erp_systems( EXPORTING iv_whno    = p_lgnum
                                         IMPORTING et_systems = DATA(system_data) ).

  IF system_data IS INITIAL.
    MESSAGE 'System data not found' TYPE 'E'.
  ENDIF.

  DATA(headers_refdoc_in) = VALUE /scdl/t_sp_a_head_refdoc( ( refdoccat = refdoc_cat_erp
                                                              refbskey  = system_data[ 1 ]-bskey ) ).

  relation_inkey = VALUE /scdl/s_sp_k_head( docid = docid ).

  delivery_sp->insert( EXPORTING aspect             = /scdl/if_sp_c=>sc_asp_head_refdoc
                                 relation           = /scdl/if_sp_c=>sc_rel_head_to_refdoc
                                 relation_inkey     = relation_inkey
                                 inrecords          = headers_refdoc_in
                       IMPORTING outrecords         = headers_refdoc_out
                                 relation_outrecord = relation_outrecord
                                 rejected           = rejected
                                 return_codes       = return_codes ).

  IF rejected = abap_true.
    messages = message_box->get_messages_with_no( ).
    cl_demo_output=>display( messages ).
    RETURN.
  ENDIF.

* ================================================================================= HU

  DATA: hu_out TYPE /scwm/t_sp_a_hu.

  DATA(hu_in) = VALUE /scwm/t_sp_a_hu( ( huno          = p_hu
                                         lgnum         = p_lgnum
                                         itemtype      = p_itemty
                                         manual_header = abap_true
                                           ) ).

  DATA(hu_relation_inkey) = VALUE /scdl/s_sp_k_head( docid = docid ).

  delivery_sp->insert( EXPORTING inrecords      = hu_in
                                 aspect         = /scwm/if_sp_c=>sc_asp_hu
                                 relation       = /scwm/if_sp_c=>sc_rel_head_to_hu
                                 relation_inkey = hu_relation_inkey
                       IMPORTING outrecords     = hu_out
                                 rejected       = rejected
                                 return_codes   = return_codes ).

  IF rejected = abap_true.
    messages = message_box->get_messages_with_no( ).
    cl_demo_output=>display( messages ).
    RETURN.
  ENDIF.

* ================================================================================= Save

  delivery_sp->/scdl/if_sp1_transaction~save( IMPORTING rejected = rejected ).

  IF rejected = abap_true.
    ROLLBACK WORK.
    messages = message_box->get_messages_with_no( ).
    cl_demo_output=>display( messages ).
    /scwm/cl_tm=>cleanup( ).
    RETURN.
  ENDIF.

  COMMIT WORK AND WAIT.
  /scwm/cl_tm=>cleanup( ).

* Get readable DOCNO for ODO created (optional)
  SELECT SINGLE docno
    INTO @DATA(delivery_number)
    FROM /scdl/db_proch_o
      WHERE docid = @docid.

  WRITE: 'YAY! Delivery created: ' , delivery_number.
