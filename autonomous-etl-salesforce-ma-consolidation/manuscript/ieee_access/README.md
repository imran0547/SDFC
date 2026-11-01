# IEEE Access version

`access_manuscript.tex` + `body.tex` + `refs.bib`, built with the official IEEE Access LaTeX template
(ACCESS_latex_template_20240429). The template's class and font files are not redistributed here:
download the template from the IEEE Access submission guidelines page and copy `ieeeaccess.cls`,
`IEEEtran.cls`, `spotcolor.sty`, `IEEEtran.bst`, the font files and logos into this folder.
Figures are read from `figures/` (copy `../figures/fig*.png`).

    pdflatex access_manuscript && bibtex access_manuscript && pdflatex access_manuscript && pdflatex access_manuscript

`body.tex` is generated from `../paper.md` by `../md2tex.py` followed by `../americanize.py`.
