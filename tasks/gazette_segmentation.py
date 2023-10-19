from associations import extrair_diarios_municipais


def extrarir_diarios(pdf_text, path_pdf, territories):

    diarios = extrair_diarios_municipais(pdf_text, path_pdf, territories)

    return diarios
