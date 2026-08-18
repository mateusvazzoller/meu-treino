# -*- coding: utf-8 -*-
"""Gera o QR do endereço do app, para colar no `index.html`.

O QR mora no HTML como um `<path>` de SVG, não como imagem: assim ele
funciona offline, acompanha o tema e não pesa nada. A contrapartida é que
ele não se atualiza sozinho — se o endereço do app mudar, rode este script
de novo e troque o `<path>` e o texto do `#iUrl` juntos.

Foi um erro real: o `meu-treino` nasceu como cópia do `taf` e ficou meses
com o QR do outro app, mandando quem lesse para o aplicativo errado.

    pip install qrcode
    python tools/gerar-qr.py
"""
import io
import sys

import qrcode

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

ENDERECO = "https://mateusvazzoller.github.io/meu-treino/"


def matriz(texto):
    """Correção M e borda 2 — o mesmo do QR que já estava no arquivo."""
    q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, border=2)
    q.add_data(texto)
    q.make(fit=True)
    return q.get_matrix()


def caminho(m):
    """Vira um `d` de SVG: cada linha escura vira um traço horizontal.

    Traço em vez de quadradinho porque, com `stroke-width:1`, um `h7` desenha
    sete módulos de uma vez — o arquivo fica uma fração do tamanho de um
    `<rect>` por módulo. O `.5` é o meio do módulo, onde a linha tem que
    passar para cobri-lo inteiro.
    """
    partes = []
    caneta_x = caneta_y = None
    for y, linha in enumerate(m):
        x = 0
        while x < len(linha):
            if not linha[x]:
                x += 1
                continue
            fim = x
            while fim < len(linha) and linha[fim]:
                fim += 1
            tamanho = fim - x
            if caneta_x is None:
                partes.append("M%d %d.5h%d" % (x, y, tamanho))
            else:
                partes.append("m%d %dh%d" % (x - caneta_x, y - caneta_y, tamanho))
            caneta_x, caneta_y = x + tamanho, y
            x = fim
    return "".join(partes)


def svg(texto):
    m = matriz(texto)
    n = len(m)
    return n, (
        '<svg class="qr" viewBox="0 0 %d %d" role="img" aria-label="QR com o endereço do app">'
        '<rect width="%d" height="%d" fill="#fff"></rect>'
        '<path stroke="#12151A" stroke-width="1" d="%s"></path></svg>'
    ) % (n, n, n, n, caminho(m))


if __name__ == "__main__":
    alvo = sys.argv[1] if len(sys.argv) > 1 else ENDERECO
    n, marcacao = svg(alvo)
    print("endereço: %s" % alvo)
    print("módulos:  %d x %d" % (n, n))
    print()
    print(marcacao)
