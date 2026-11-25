*&---------------------------------------------------------------------*
*& Exemplo de uso no nó "Código de programa" do Smartform
*&---------------------------------------------------------------------*
*& Variáveis globais do Smartform (aba "Definições globais"):
*&   W_QRCODE TYPE TDOBNAME  -> nome do gráfico gerado
*&
*& No nó "Gráfico" do Smartform:
*&   Nome     : &W_QRCODE&
*&   Objeto   : GRAPHICS
*&   ID       : BMAP
*&   Tipo     : Colorido (BCOL)
*&---------------------------------------------------------------------*

DATA: lv_conteudo  TYPE string,
      lv_bmap_name TYPE tdobname.

IF is_dados-qr_conteudo IS NOT INITIAL.

* Nome único por registro, para não sobrescrever o QR de outra
* impressão feita ao mesmo tempo
  CONCATENATE 'ZQRCODE' is_dados-id_registro
         INTO lv_bmap_name SEPARATED BY '_'.

* Conteúdo puro: a função já faz a codificação de URL
  lv_conteudo = is_dados-qr_conteudo.

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
    w_qrcode = lv_bmap_name.
  ELSE.
*   Sem QR Code: o nó Gráfico fica vazio. Trate como preferir
*   (log, mensagem, condição no nó para não exibir).
    CLEAR w_qrcode.
  ENDIF.

ENDIF.
