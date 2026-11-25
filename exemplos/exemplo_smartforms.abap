*&---------------------------------------------------------------------*
*& Exemplo de uso no nó "Código de programa" do Smartform
*&---------------------------------------------------------------------*
*& Variáveis globais do Smartform (aba "Definições globais"):
*&   W_PIX   TYPE TDOBNAME   -> nome do gráfico gerado (QR do PIX)
*&
*& No nó "Gráfico" do Smartform:
*&   Nome     : &W_PIX&
*&   Objeto   : GRAPHICS
*&   ID       : BMAP
*&   Tipo     : Colorido (BCOL)
*&---------------------------------------------------------------------*

DATA: lv_conteudo  TYPE string,
      lv_bmap_name TYPE tdobname.

IF is_dados-qr_code_pix IS NOT INITIAL.

* Nome único por documento, para não sobrescrever o QR de outra nota
* impressa ao mesmo tempo
  CONCATENATE 'ZQRPIX' is_dados-id_documento
         INTO lv_bmap_name SEPARATED BY '_'.

* Conteúdo puro: a função já faz a codificação de URL
  lv_conteudo = is_dados-qr_code_pix.

  CALL FUNCTION 'Z_GERA_QRCODE_BMAP'
    EXPORTING
      iv_conteudo       = lv_conteudo
      iv_bmap_name      = lv_bmap_name
      iv_tamanho        = 100
    EXCEPTIONS
      http_error        = 1
      igs_error         = 2
      conversion_failed = 3
      enqueue_failed    = 4
      OTHERS            = 5.

  IF sy-subrc = 0.
    w_pix = lv_bmap_name.
  ELSE.
*   Sem QR Code: o nó Gráfico fica vazio. Trate como preferir
*   (log, mensagem, condição no nó para não exibir).
    CLEAR w_pix.
  ENDIF.

ENDIF.
