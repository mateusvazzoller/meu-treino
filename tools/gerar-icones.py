"""Gera os ícones do app "Meu Treino".

    python tools/gerar-icones.py

Requer Pillow. Os arquivos vão para icons/ e devem ser commitados.

A marca é um **T construído**: o travessão é a barra e a haste desce
como o corpo. Uma letra só, desenhada como objeto — não é texto tipografado.
Foi o formato escolhido depois de comparar sete conceitos no tamanho real de
48 px, que é o que vale: símbolo com muitos elementos vira borrão ali.

Medidas seguem as regras de ícone de app:

  * fundo sólido azul, marca escura — silhueta garantida em qualquer papel
    de parede. Ícone escuro some em tela inicial preta.
  * duas cores, sem degradê, sem sombra, sem contorno fino
  * traço de 58 px no master de 512 (11%); o piso praticável é 32 px
  * marca ocupando ~68% da largura na versão comum

Três famílias de arquivo, e a diferença entre elas importa:

  any        cantos arredondados no PNG, marca a 68%. Usado no diálogo de
             instalação, na aba do navegador e no alternador de tarefas.
  maskable   quadrado sangrando até a borda, sem canto arredondado, marca
             reduzida a 58%. O Android recorta o ícone em formatos diferentes
             por aparelho (círculo, quadrado, gota) — a zona garantida é o
             círculo de raio 40% a partir do centro. Sem esta versão, o
             launcher desenha o PNG dentro de uma moldura branca.
  monochrome silhueta chapada para os "ícones temáticos" do Android 13+.

O apple-touch-icon também vai sem canto arredondado: o iOS aplica a máscara
dele por cima, e arredondar antes cria borda dupla.
"""

import os
from PIL import Image, ImageDraw

ESCURO = (18, 21, 26, 255)     # --ground
ACCENT = (74, 144, 255, 255)   # --accent (azul: o Meu TAF é laranja e os dois
                               # convivem na mesma tela inicial)
BRANCO = (255, 255, 255, 255)

M = 512                        # master: desenha grande e reduz
RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DESTINO = os.path.join(RAIZ, "icons")


def marca(d, cor, esc):
    """T construído, centrado no quadro de M×M."""
    cx = M / 2
    larg = 350 * esc          # travessão (a barra fixa)
    esp = 58 * esc            # espessura do travessão
    haste = 66 * esc          # largura da haste
    alt = 300 * esc           # altura total da marca
    y0 = cx - alt / 2
    d.rounded_rectangle([cx - larg / 2, y0, cx + larg / 2, y0 + esp],
                        radius=esp * 0.14, fill=cor)
    d.rounded_rectangle([cx - haste / 2, y0 + esp, cx + haste / 2, y0 + alt],
                        radius=haste * 0.14, fill=cor)


def gerar(nome, tamanho, tipo="any"):
    img = Image.new("RGBA", (M, M), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if tipo == "mono":
        marca(d, BRANCO, 0.85)          # silhueta, sem fundo
    elif tipo == "maskable":
        d.rectangle([0, 0, M, M], fill=ACCENT)
        marca(d, ESCURO, 0.85)          # cabe no círculo de raio 205
    elif tipo == "quadrado":            # apple-touch-icon
        d.rectangle([0, 0, M, M], fill=ACCENT)
        marca(d, ESCURO, 1.0)
    else:
        d.rounded_rectangle([0, 0, M - 1, M - 1], radius=int(M * 0.22), fill=ACCENT)
        marca(d, ESCURO, 1.0)

    if tamanho != M:
        img = img.resize((tamanho, tamanho), Image.LANCZOS)
    caminho = os.path.join(DESTINO, nome)
    img.save(caminho)
    print("gerado: %-28s %d px" % (nome, tamanho))


if __name__ == "__main__":
    os.makedirs(DESTINO, exist_ok=True)
    gerar("icon-192.png", 192)
    gerar("icon-512.png", 512)
    gerar("icon-192-maskable.png", 192, "maskable")
    gerar("icon-maskable-512.png", 512, "maskable")
    gerar("icon-mono-512.png", 512, "mono")
    gerar("apple-touch-icon.png", 180, "quadrado")
