*&---------------------------------------------------------------------*
*& Include LZQRCODETOP - Declarações globais do grupo de funções ZQRCODE
*&---------------------------------------------------------------------*
*& Gera QR Code como bitmap (BMAP) na SE78 para uso em Smartforms /
*& SAPscript, sem depender de suporte nativo a QR Code no SAP.
*&---------------------------------------------------------------------*
FUNCTION-POOL zqrcode.

TYPE-POOLS: sbdst.

* Constantes usadas pela SE78 para gravar gráficos no BDS
* (mesmos valores usados pelo programa standard de upload de bitmaps)
CONSTANTS: c_bds_classname TYPE sbdst_classname VALUE 'DEVC_STXD_BITMAP',
           c_bds_classtype TYPE sbdst_classtype VALUE 'OT',
           c_bds_mimetype  TYPE bds_mimetp      VALUE 'application/octet-stream'.

* Tamanho (px) da imagem solicitada à API. A imagem é redimensionada
* depois pelo IGS para o tamanho final informado na função.
CONSTANTS: c_tamanho_api TYPE string VALUE '250x250'.

DATA: gv_url        TYPE string,                    " URL da API de QR Code
      go_http       TYPE REF TO if_http_client,     " Cliente HTTP
      gv_png        TYPE xstring,                   " Imagem PNG recebida
      gv_png_len    TYPE i,                         " Tamanho do PNG (bytes)
      gt_png_mime   TYPE w3mimetabtype,             " PNG em tabela binária
      go_igs        TYPE REF TO cl_igs_image_converter, " Conversor IGS
      gt_bmp        TYPE w3mimetabtype,             " Imagem BMP convertida
      gv_bmp_size   TYPE w3param-cont_len,          " Tamanho do BMP
      gv_bmp_type   TYPE w3param-cont_type,         " MIME type do BMP
      gv_docid      TYPE stxbitmaps-docid,          " ID do documento BDS
      gv_resolution TYPE stxbitmaps-resolution.     " Resolução (DPI)
