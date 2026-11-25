*&---------------------------------------------------------------------*
*& Include LZQRCODEF01 - Subrotinas do grupo de funções ZQRCODE
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form f_refresh_values
*&---------------------------------------------------------------------*
*& Limpa as variáveis globais entre uma chamada e outra (a função pode
*& ser chamada várias vezes no mesmo processo, ex.: QR PIX + consulta).
*&---------------------------------------------------------------------*
FORM f_refresh_values.

  CLEAR: gv_url,
         go_http,
         gv_png,
         gv_png_len,
         gt_png_mime,
         go_igs,
         gt_bmp,
         gv_bmp_size,
         gv_bmp_type,
         gv_docid,
         gv_resolution.

ENDFORM.                    "f_refresh_values

*&---------------------------------------------------------------------*
*& Form f_encode_url
*&---------------------------------------------------------------------*
*& Codifica os caracteres que quebram a query string da URL.
*& O '%' precisa ser o primeiro, senão os códigos gerados depois
*& seriam codificados de novo.
*&---------------------------------------------------------------------*
FORM f_encode_url CHANGING cv_texto TYPE string.

  REPLACE ALL OCCURRENCES OF '%' IN cv_texto WITH '%25'.
  REPLACE ALL OCCURRENCES OF '&' IN cv_texto WITH '%26'.
  REPLACE ALL OCCURRENCES OF '#' IN cv_texto WITH '%23'.
  REPLACE ALL OCCURRENCES OF '+' IN cv_texto WITH '%2B'.
  REPLACE ALL OCCURRENCES OF ' ' IN cv_texto WITH '%20'.

ENDFORM.                    "f_encode_url

*&---------------------------------------------------------------------*
*& Form f_download_qrcode
*&---------------------------------------------------------------------*
*& Chama a API pública api.qrserver.com e recebe o QR Code em PNG.
*&---------------------------------------------------------------------*
FORM f_download_qrcode USING uv_conteudo TYPE string.

  DATA: lv_dados  TYPE string,
        lv_status TYPE i.

  lv_dados = uv_conteudo.
  PERFORM f_encode_url CHANGING lv_dados.

  CONCATENATE 'http://api.qrserver.com/v1/create-qr-code/?size='
              c_tamanho_api
              '&data='
              lv_dados
         INTO gv_url.

  cl_http_client=>create_by_url(
    EXPORTING
      url                = gv_url
    IMPORTING
      client             = go_http
    EXCEPTIONS
      argument_not_found = 1
      plugin_not_active  = 2
      internal_error     = 3
      OTHERS             = 4 ).

  IF sy-subrc <> 0.
    RAISE http_error.
  ENDIF.

  go_http->send(
    EXCEPTIONS
      http_communication_failure = 1
      http_invalid_state         = 2
      http_processing_failed     = 3
      http_invalid_timeout       = 4
      OTHERS                     = 5 ).

  IF sy-subrc <> 0.
    go_http->close( ).
    RAISE http_error.
  ENDIF.

  go_http->receive(
    EXCEPTIONS
      http_communication_failure = 1
      http_invalid_state         = 2
      http_processing_failed     = 3
      OTHERS                     = 4 ).

  IF sy-subrc <> 0.
    go_http->close( ).
    RAISE http_error.
  ENDIF.

  go_http->response->get_status( IMPORTING code = lv_status ).

  gv_png = go_http->response->get_data( ).

  go_http->close( ).

  IF lv_status <> 200 OR gv_png IS INITIAL.
    RAISE http_error.
  ENDIF.

  gv_png_len = xstrlen( gv_png ).

* XSTRING -> tabela binária (formato esperado pelo IGS)
  CALL FUNCTION 'RSFO_XSTRING_TO_MIME'
    EXPORTING
      c_xstring = gv_png
      i_length  = gv_png_len
    TABLES
      c_t_mime  = gt_png_mime.

ENDFORM.                    "f_download_qrcode

*&---------------------------------------------------------------------*
*& Form f_convert_image
*&---------------------------------------------------------------------*
*& Converte PNG -> BMP via IGS e grava o gráfico na SE78.
*&---------------------------------------------------------------------*
FORM f_convert_image USING uv_bmap_name TYPE tdobname
                           uv_tamanho   TYPE i.

  DATA: lv_name       TYPE stxbitmaps-tdname,
        lv_object     TYPE stxbitmaps-tdobject,
        lv_id         TYPE stxbitmaps-tdid,
        lv_btype      TYPE stxbitmaps-tdbtype,
        lv_resident   TYPE stxbitmaps-resident,
        lv_autoheight TYPE stxbitmaps-autoheight,
        lv_bmcomp     TYPE stxbitmaps-bmcomp,
        lv_extension  TYPE c LENGTH 3,
        lv_title      TYPE bds_description.

  CREATE OBJECT go_igs.

  go_igs->input  = 'image/png'.
  go_igs->output = 'image/bmp'.
  go_igs->width  = uv_tamanho.
  go_igs->height = uv_tamanho.

  CALL METHOD go_igs->set_image
    EXPORTING
      blob      = gt_png_mime
      blob_size = gv_png_len.

  CALL METHOD go_igs->execute
    EXCEPTIONS
      communication_error = 1
      internal_error      = 2
      external_error      = 3
      OTHERS              = 4.

  IF sy-subrc <> 0.
    RAISE igs_error.
  ENDIF.

  CALL METHOD go_igs->get_image
    IMPORTING
      blob      = gt_bmp
      blob_size = gv_bmp_size
      blob_type = gv_bmp_type.

  lv_name       = uv_bmap_name.   " Nome do gráfico na SE78
  lv_object     = 'GRAPHICS'.
  lv_id         = 'BMAP'.
  lv_btype      = 'BCOL'.         " Colorido. Preto e branco: 'BMON'
  lv_resident   = space.
  lv_autoheight = 'X'.
  lv_bmcomp     = 'X'.
  lv_extension  = 'BMP'.
  lv_title      = space.

* Se o gráfico já existe na SE78, reaproveita o DOCID para atualizar
* o mesmo documento BDS em vez de criar um novo a cada execução.
  SELECT SINGLE docid
    FROM stxbitmaps
    INTO gv_docid
   WHERE tdobject = lv_object
     AND tdname   = lv_name
     AND tdid     = lv_id
     AND tdbtype  = lv_btype.

  IF sy-subrc <> 0.
    CLEAR gv_docid.
  ENDIF.

  PERFORM f_import_bitmap_bds USING gt_bmp
                                    lv_name
                                    lv_object
                                    lv_id
                                    lv_btype
                                    lv_extension
                                    lv_title
                                    lv_resident
                                    lv_autoheight
                                    lv_bmcomp
                           CHANGING gv_docid
                                    gv_resolution.

ENDFORM.                    "f_convert_image

*&---------------------------------------------------------------------*
*& Form f_import_bitmap_bds
*&---------------------------------------------------------------------*
*& Grava o bitmap no BDS e o cabeçalho na STXBITMAPS. Reproduz o que a
*& SE78 faz ao importar um gráfico manualmente.
*&---------------------------------------------------------------------*
FORM f_import_bitmap_bds
        USING    p_blob       TYPE w3mimetabtype
                 p_name       TYPE stxbitmaps-tdname
                 p_object     TYPE stxbitmaps-tdobject
                 p_id         TYPE stxbitmaps-tdid
                 p_btype      TYPE stxbitmaps-tdbtype
                 p_format     TYPE c
                 p_title      TYPE bds_description
                 p_resident   TYPE stxbitmaps-resident
                 p_autoheight TYPE stxbitmaps-autoheight
                 p_bmcomp     TYPE stxbitmaps-bmcomp
        CHANGING p_docid      TYPE stxbitmaps-docid
                 p_resolution TYPE stxbitmaps-resolution.

  DATA: l_object_key      TYPE sbdst_object_key,
        l_tab             TYPE ddobjname,
        l_bytecount       TYPE i,
        l_bds_bytecount   TYPE i,
        l_width_tw        TYPE stxbitmaps-widthtw,
        l_height_tw       TYPE stxbitmaps-heighttw,
        l_width_pix       TYPE stxbitmaps-widthpix,
        l_height_pix      TYPE stxbitmaps-heightpix,
        l_bds_object      TYPE REF TO cl_bds_document_set,
        l_bds_content     TYPE sbdst_content,
        l_bds_components  TYPE sbdst_components,
        wa_bds_components TYPE LINE OF sbdst_components,
        l_bds_signature   TYPE sbdst_signature,
        wa_bds_signature  TYPE LINE OF sbdst_signature,
        l_bds_properties  TYPE sbdst_properties,
        wa_bds_properties TYPE LINE OF sbdst_properties,
        wa_stxbitmaps     TYPE stxbitmaps.

*----------------------------------------------------------------------
* 1. Bloqueia o gráfico
*----------------------------------------------------------------------
  PERFORM f_enqueue_graphic USING p_object
                                  p_name
                                  p_id
                                  p_btype.

*----------------------------------------------------------------------
* 2. Converte o BMP para o formato interno do SAPscript/Smartforms
*----------------------------------------------------------------------
  l_bytecount = gv_bmp_size.

  CALL FUNCTION 'SAPSCRIPT_CONVERT_BITMAP_BDS'
    EXPORTING
      color                    = 'X'
      format                   = p_format
      resident                 = p_resident
      bitmap_bytecount         = l_bytecount
      compress_bitmap          = p_bmcomp
    IMPORTING
      width_tw                 = l_width_tw
      height_tw                = l_height_tw
      width_pix                = l_width_pix
      height_pix               = l_height_pix
      dpi                      = p_resolution
      bds_bytecount            = l_bds_bytecount
    TABLES
      bitmap_file              = p_blob
      bitmap_file_bds          = l_bds_content
    EXCEPTIONS
      format_not_supported     = 1
      no_bmp_file              = 2
      bmperr_invalid_format    = 3
      bmperr_no_colortable     = 4
      bmperr_unsup_compression = 5
      bmperr_corrupt_rle_data  = 6
      OTHERS                   = 7.

  IF sy-subrc <> 0.
    PERFORM f_dequeue_graphic USING p_object
                                    p_name
                                    p_id
                                    p_btype.
    RAISE conversion_failed.
  ENDIF.

*----------------------------------------------------------------------
* 3. Grava o conteúdo no BDS (cria ou atualiza)
*----------------------------------------------------------------------
  CREATE OBJECT l_bds_object.

  wa_bds_components-doc_count  = '1'.
  wa_bds_components-comp_count = '1'.
  wa_bds_components-mimetype   = c_bds_mimetype.
  wa_bds_components-comp_size  = l_bds_bytecount.
  APPEND wa_bds_components TO l_bds_components.

  IF p_docid IS INITIAL.
*   Gráfico novo
    PERFORM f_bds_create TABLES   l_bds_components
                                  l_bds_content
                                  l_bds_signature
                         USING    l_bds_object
                         CHANGING l_object_key
                                  p_docid.
  ELSE.
*   Gráfico já existe: busca a OBJECT_KEY para atualizar
    CLEAR l_object_key.

    SELECT SINGLE * FROM stxbitmaps INTO wa_stxbitmaps
     WHERE tdobject = p_object
       AND tdid     = p_id
       AND tdname   = p_name
       AND tdbtype  = p_btype.

    SELECT SINGLE tabname FROM bds_locl INTO l_tab
     WHERE classname = c_bds_classname
       AND classtype = c_bds_classtype.

    IF sy-subrc = 0.
      SELECT SINGLE object_key FROM (l_tab) INTO l_object_key
       WHERE loio_id   = wa_stxbitmaps-docid+10(32)
         AND classname = c_bds_classname
         AND classtype = c_bds_classtype.
    ENDIF.

    CALL METHOD l_bds_object->update_with_table
      EXPORTING
        classname     = c_bds_classname
        classtype     = c_bds_classtype
        object_key    = l_object_key
        doc_id        = p_docid
        doc_ver_no    = '1'
        doc_var_id    = '1'
      CHANGING
        components    = l_bds_components
        content       = l_bds_content
      EXCEPTIONS
        nothing_found = 1
        OTHERS        = 2.

    IF sy-subrc = 1.
*     Inconsistência STXBITMAPS x BDS: cria o documento de novo
      PERFORM f_bds_create TABLES   l_bds_components
                                    l_bds_content
                                    l_bds_signature
                           USING    l_bds_object
                           CHANGING l_object_key
                                    p_docid.
    ENDIF.
  ENDIF.

*----------------------------------------------------------------------
* 4. Grava o cabeçalho do gráfico na STXBITMAPS (o que a SE78 lista)
*----------------------------------------------------------------------
  CLEAR wa_stxbitmaps.
  wa_stxbitmaps-tdname     = p_name.
  wa_stxbitmaps-tdobject   = p_object.
  wa_stxbitmaps-tdid       = p_id.
  wa_stxbitmaps-tdbtype    = p_btype.
  wa_stxbitmaps-docid      = p_docid.
  wa_stxbitmaps-widthpix   = l_width_pix.
  wa_stxbitmaps-heightpix  = l_height_pix.
  wa_stxbitmaps-widthtw    = l_width_tw.
  wa_stxbitmaps-heighttw   = l_height_tw.
  wa_stxbitmaps-resolution = p_resolution.
  wa_stxbitmaps-resident   = p_resident.
  wa_stxbitmaps-autoheight = p_autoheight.
  wa_stxbitmaps-bmcomp     = p_bmcomp.

  INSERT INTO stxbitmaps VALUES wa_stxbitmaps.
  IF sy-subrc <> 0.
    UPDATE stxbitmaps FROM wa_stxbitmaps.
  ENDIF.

*----------------------------------------------------------------------
* 5. Descrição do documento no BDS
*----------------------------------------------------------------------
  wa_bds_properties-prop_name  = 'DESCRIPTION'.
  wa_bds_properties-prop_value = p_title.
  APPEND wa_bds_properties TO l_bds_properties.

  CALL METHOD l_bds_object->change_properties
    EXPORTING
      classname  = c_bds_classname
      classtype  = c_bds_classtype
      object_key = l_object_key
      doc_id     = p_docid
      doc_ver_no = '1'
      doc_var_id = '1'
    CHANGING
      properties = l_bds_properties
    EXCEPTIONS
      OTHERS     = 1.

*----------------------------------------------------------------------
* 6. Desbloqueia
*----------------------------------------------------------------------
  PERFORM f_dequeue_graphic USING p_object
                                  p_name
                                  p_id
                                  p_btype.

ENDFORM.                    "f_import_bitmap_bds

*&---------------------------------------------------------------------*
*& Form f_bds_create
*&---------------------------------------------------------------------*
*& Cria o documento no BDS e devolve o DOCID gerado.
*&---------------------------------------------------------------------*
FORM f_bds_create TABLES   pt_components TYPE sbdst_components
                           pt_content    TYPE sbdst_content
                           pt_signature  TYPE sbdst_signature
                  USING    po_bds        TYPE REF TO cl_bds_document_set
                  CHANGING cv_object_key TYPE sbdst_object_key
                           cv_docid      TYPE stxbitmaps-docid.

  DATA: lt_components TYPE sbdst_components,
        lt_content    TYPE sbdst_content,
        lt_signature  TYPE sbdst_signature,
        ls_signature  TYPE LINE OF sbdst_signature.

  lt_components = pt_components[].
  lt_content    = pt_content[].

  ls_signature-doc_count = '1'.
  APPEND ls_signature TO lt_signature.

  CALL METHOD po_bds->create_with_table
    EXPORTING
      classname  = c_bds_classname
      classtype  = c_bds_classtype
      components = lt_components
      content    = lt_content
    CHANGING
      signature  = lt_signature
      object_key = cv_object_key
    EXCEPTIONS
      OTHERS     = 1.

  IF sy-subrc = 0.
    READ TABLE lt_signature INDEX 1 INTO ls_signature
      TRANSPORTING doc_id.
    IF sy-subrc = 0.
      cv_docid = ls_signature-doc_id.
    ENDIF.
  ENDIF.

  pt_signature[] = lt_signature.

ENDFORM.                    "f_bds_create

*&---------------------------------------------------------------------*
*& Form f_enqueue_graphic
*&---------------------------------------------------------------------*
FORM f_enqueue_graphic USING p_object TYPE stxbitmaps-tdobject
                             p_name   TYPE stxbitmaps-tdname
                             p_id     TYPE stxbitmaps-tdid
                             p_btype  TYPE stxbitmaps-tdbtype.

  CALL FUNCTION 'ENQUEUE_ESSGRABDS'
    EXPORTING
      tdobject       = p_object
      tdname         = p_name
      tdid           = p_id
      tdbtype        = p_btype
    EXCEPTIONS
      foreign_lock   = 1
      system_failure = 2
      OTHERS         = 3.

  IF sy-subrc <> 0.
    RAISE enqueue_failed.
  ENDIF.

ENDFORM.                    "f_enqueue_graphic

*&---------------------------------------------------------------------*
*& Form f_dequeue_graphic
*&---------------------------------------------------------------------*
FORM f_dequeue_graphic USING p_object TYPE stxbitmaps-tdobject
                             p_name   TYPE stxbitmaps-tdname
                             p_id     TYPE stxbitmaps-tdid
                             p_btype  TYPE stxbitmaps-tdbtype.

  CALL FUNCTION 'DEQUEUE_ESSGRABDS'
    EXPORTING
      tdobject = p_object
      tdname   = p_name
      tdid     = p_id
      tdbtype  = p_btype.

ENDFORM.                    "f_dequeue_graphic
