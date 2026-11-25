FUNCTION z_gera_qrcode_bmap.
*"----------------------------------------------------------------------
*"*"Interface local:
*"  IMPORTING
*"     VALUE(IV_CONTEUDO) TYPE  STRING
*"     VALUE(IV_BMAP_NAME) TYPE  TDOBNAME
*"     VALUE(IV_TAMANHO) TYPE  I DEFAULT 100
*"  EXCEPTIONS
*"      HTTP_ERROR
*"      IGS_ERROR
*"      CONVERSION_FAILED
*"      ENQUEUE_FAILED
*"----------------------------------------------------------------------
*& Gera um QR Code com o conteúdo informado e grava como gráfico BMAP
*& na SE78 (objeto GRAPHICS, ID BMAP, tipo BCOL) com o nome IV_BMAP_NAME.
*&
*& Depois de chamada, o Smartform exibe o QR Code em um nó "Gráfico"
*& apontando para o nome gerado (ex.: &W_QRCODE&).
*&
*& Fluxo:
*&   1. Monta a URL da API pública de QR Code com o conteúdo codificado
*&   2. Baixa a imagem PNG via HTTP (CL_HTTP_CLIENT)
*&   3. Converte PNG -> BMP pelo IGS (CL_IGS_IMAGE_CONVERTER)
*&   4. Grava o BMP no BDS + STXBITMAPS (mesma lógica da SE78)
*&----------------------------------------------------------------------

  PERFORM f_refresh_values.

  PERFORM f_download_qrcode USING iv_conteudo.

  PERFORM f_convert_image USING iv_bmap_name
                                iv_tamanho.

  FREE go_igs.

ENDFUNCTION.
