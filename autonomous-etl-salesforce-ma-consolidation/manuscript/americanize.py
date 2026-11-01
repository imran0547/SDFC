import re,sys
p=sys.argv[1]; s=open(p,encoding='utf8').read()
pairs=[("organisation","organization"),("Organisation","Organization"),("synchronis","synchroniz"),("Synchronis","Synchroniz"),
("normalis","normaliz"),("optimis","optimiz"),("characteris","characteriz"),("emphasis","emphasiz"),
("anonymis","anonymiz"),("labelled","labeled"),("labelling","labeling"),("modelling","modeling"),("behaviour","behavior"),
("catalogue","catalog"),("recognis","recogniz"),("summaris","summariz"),("utilis","utiliz"),("prioritis","prioritiz"),("standardis","standardiz"),("vectoris","vectoriz")]
for a,b in pairs: s=s.replace(a,b)
s=s.replace("emphasize","emphasize").replace("emphasizes","emphasizes")
# 'emphasis' as noun should stay: revert 'emphasizs'? guard common noun usage
s=s.replace("emphasize ","emphasize ").replace("an emphasize","an emphasis").replace("emphasizes on","emphasis on")
open(p,'w',encoding='utf8').write(s)
