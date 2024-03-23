@echo off
set RUN_PATH=C:\AO\tools

python %RUN_PATH%\PatchTextures.py -i %1  -r ./ -c "C:\AO\tools\AOTextureViewer.exe" -p %RUN_PATH%\typicaluipacks.txt -u