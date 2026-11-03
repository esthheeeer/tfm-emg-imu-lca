%% ANALISIS TFM (LCA): EMG + IMU + MVC - MEDIA POR EJERCICIO  (v3.2, P4)
%
% LADO OPERADO DE P4: DERECHO.
% PARA OTRO PACIENTE: cambiar paciente, ladoOperado, archivosTarea, archivosMVC y modoSegmentacion.
clear; clc; close all;

%% ============================================================
% 1. CONFIGURACION GENERAL
% =============================================================
paciente    = 'P4';
ladoOperado = 'D';          % <<< 'D': lado de la rodilla intervenida

mvcManual = struct();       % ej.: mvcManual.VM_I = 150;  (en uV RMS)
% P4: el MVC de VM_D (418,2 uV) es 2,7 veces el del segundo ensayo (155,8 uV) y VL_D, que comparte
% nodo, no cambia. Descomentar SOLO si la senal cruda de MVC3 (VM_D) muestra un artefacto:
% mvcManual.VM_D = 155.77;

FsEMG = 2000; fLow = 20; fHigh = 450; ventanaRMS_s = 0.250;

archivosTarea = {'S1.csv','S2.csv','S3.csv', ...
                 'ED1.csv','ED2.csv','ED3.csv', ...
                 'EI1.csv','EI2.csv','EI3.csv'};

nombreEjercicio = containers.Map( ...
    {'S',                  'ED',               'EI'}, ...
    {'Sentarse-levantarse','Ejercicio ED',     'Ejercicio EI'});

% Senal de segmentacion: 'ambas' | 'D' | 'I' (rodilla) | 'HD' | 'HI' (cadera) | 'VLD' | 'VLI' (EMG del VL)
% [v3.2] ED con el VL D y EI con el VL I (lado que inicia el ejercicio). Si no mejora, volver a 'HD' / 'I'.
modoSegmentacion = containers.Map({'S','ED','EI'},{'ambas','VLD','VLI'});
% [v3.2] validacion: un modo desconocido ya no cae en 'ambas' sin avisar
modosSegValidos = {'ambas','D','I','HD','HI','VLD','VLI'};
for kk = keys(modoSegmentacion)
    if ~any(strcmp(modoSegmentacion(kk{1}),modosSegValidos))
        error('modoSegmentacion("%s") = "%s" no es válido. Opciones: %s.', ...
            kk{1},modoSegmentacion(kk{1}),strjoin(modosSegValidos,', '));
    end
end

% Deteccion automatica del reposo
ventanaReposo_s  = 1.5;
busquedaReposo_s = 10;
reposoManual = containers.Map('KeyType','char','ValueType','any');   % reposoManual('S1.csv') = [0.2 1.0];

ejePorArchivo = true;
maxHuecoQ_s   = 1.0;

% ---- CADERA ----
%   'inclinacionMuslo'   angulo sagital del muslo respecto a la vertical
%   'porRepeticionMuslo' muslo respecto al inicio de cada repeticion (sin pelvis)
%   'porRepeticion'      pelvis->muslo respecto al inicio de cada repeticion
%   'continuo'           pelvis->muslo continuo con mascaras 
modoCadera            = 'inclinacionMuslo';
cfgInc = struct('minVert',0.80, ...      % |z| minimo del eje largo del muslo en reposo (0.8 = hasta ~37 grados de la vertical)
                'tiltMinF',30, ...       % grados de inclinacion a partir de los que se fija el sentido "adelante"
                'minConsist',0.60);      % consistencia minima de esa direccion (0-1)
minExplCadera         = 0.90;   % [porRepeticion*] fraccion minima de la rotacion en UN eje
maxAnguloCadera_deg   = 140;    % |angulo| mayor => no fisiologico
cierreRepCadera_deg   = 40;     % [porRepeticion*, continuo] |angulo al final de la repeticion|
maxSaltoAngulo_deg    = 10;     % [continuo] salto maximo entre muestras (glitch)
margenSalto_s         = 0.10;   % [continuo]
ventanaBase_s         = 4;      % [continuo]
maxBaseCadera_deg     = 50;     % [continuo]

% Intervalo activo
umbralMovimiento_deg    = 8;
duracionMinMovimiento_s = 0.25;
rellenoHuecos_s         = 0.20;

% Repeticiones
distanciaMinPicos_s  = 0.8;
% Distancia minima entre picos por ejercicio (s). Dejar 0,8 y subir SOLO si Duracion_rep_s de un
% ejercicio sale la mitad que en los demas (doble conteo; en P2 'EI' hizo falta 2,2 s).
% [v3.2] ED y EI con 2,0 s: el ciclo dura ~2,1-3,6 s y 2,0 s evita los picos secundarios del VL sin
% fusionar ciclos cortos. Ajustar tras ver Duracion_rep_s y las figuras de movimiento real.
distanciaMinPicosEj = containers.Map({'S','ED','EI'},{0.8,2.0,2.0});
% Relleno (s) que se anade al final del intervalo activo SOLO para segmentar (el valle final de la
% ultima repeticion queda fuera cuando la rodilla baja de 8 grados).
% [v3.2] Valor ACTIVO: S = 1,0 s (heredado de P1/P2); ED y EI = 0. Si ED3 tiene un 5.o paso (~17 s) sin
% contar, probar ED = 1.0.
padFinalSeg_s = containers.Map({'S','ED','EI'},{1.0,0,0});
% Se descartan repeticiones con duracion < fracDurMinRep x mediana de su archivo (fragmentos)
fracDurMinRep = 0.5;
% Solo modos 'VLD'/'VLI' (EMG): prominencia minima (%MVC), fraccion de la prominencia maxima y tolerancia
promMinVLD_pct = 15;  fracPromVLD = 0.35;  tolCentrado = 0.25;
prominenciaMin_deg   = 8;
fraccionProminencia  = 0.5;
incluirRepIncompleta = false;
nPuntos = 101;
% true: el EMG de un lado NO se descarta cuando falta la senal cinematica de ese lado.
% false = comportamiento de P1/P2 (se descarta). Probar true si N_validas del EMG cae mucho.
emgIndependienteCinematica = false;

% Desfase izquierda-derecha (solo ejercicios simetricos). En P4 los muslos ya estan sincronizados.
alinearLados         = false;
ejerciciosSimetricos = {'S'};
maxLagLados_s        = 1.5;
umbralValidezAlinear = 0.6;
minLagCorregir_s     = 0.10;   % no se corrige si |lag| es menor
minMejoraCorr        = 0.05;   % la correlacion D-I debe mejorar al menos esto tras alinear

% Exclusion manual de repeticiones por ventana temporal (s), por archivo
excluirVentana = containers.Map('KeyType','char','ValueType','any');   % ej.: excluirVentana('EI2.csv') = [5 10.5];
% excluirVentana('ED2.csv') = [0 3];   % alternativa minima si la segmentacion no elimina las reps espurias
% ROM de una articulacion que se descarta en un archivo (la senal sigue en las curvas y en el EMG).
% Valores: 'hipD','hipI','kneeD','kneeI'.
excluirROM = containers.Map('KeyType','char','ValueType','any');       % ej.: excluirROM('S3.csv') = {'kneeD'};
% P4, candidatos (decidir tras ver el ROM con la nueva segmentacion):
% excluirROM('ED2.csv') = {'kneeD'};   % eje 78 %, signo ambiguo, |cos| global 0,75
% excluirROM('EI3.csv') = {'kneeD'};   % eje 61 %, |cos| global 0,58

recorteManual = containers.Map('KeyType','char','ValueType','any');

% MVC
fracMinEnsayoMVC  = 0.05;
fracMinMVCvsTarea = 0.02;
% Calidad
umbralNoInterpEje = 0.60;
umbralEje         = 0.85;
fracRepsSobre100  = 0.20;
nMinROM           = 5;     % n efectivo minimo de repeticiones validas (operada y sana) para que el ROM tenga calidad > 0
umbralCanalPlano_pct = 5;  % pico (%MVC) por debajo del cual un lado se considera SIN SENAL en toda la tarea
ejeArchivoAnulaCalidad = false;  % true: eje por archivo <60 % => calidad ROM 0 (false: tope 1)
% Ajustes manuales de calidad: clave 'Variable|Tarea' (Tarea = 'S' o 'Step'), valor 0/1/2
calidadManual = containers.Map('KeyType','char','ValueType','double');

% Figuras
figurasPorArchivo        = false;
figurasMovimientoReal    = true;
figurasMediaPorEjercicio = true;
figurasComparacion       = true;
mostrarFigurasEnPantalla = false;
carpetaFiguras           = [paciente '_figuras'];
if ~isfolder(carpetaFiguras), mkdir(carpetaFiguras); end

%% ============================================================
% 2. MUSCULOS Y COLUMNAS
% =============================================================
musculos = {'VM_D','VL_D','VM_I','VL_I','GM_D','GM_I','BF_D','BF_I'};
nombreMusculo = containers.Map(musculos, { ...
    'Vasto medial D','Vasto lateral D','Vasto medial I','Vasto lateral I', ...
    'Glúteo medio D','Glúteo medio I','Isquiotibiales D (bíceps femoral)', ...
    'Isquiotibiales I (bíceps femoral)'});

paresBase   = {'VM','VL','GM','BF'};
nombreBase  = {'Vasto medial','Vasto lateral','Glúteo medio','Isquiotibiales'};

% CSV de 49 columnas: 8 nodos con 2 canales EMG + 4 de cuaternion
%  nodo1 (2-7): GM D | nodo2 (8-13): VM D, VL D | nodo3 (14-19): BF D
%  nodo4 (20-25): GM I | nodo5 (26-31): tibia D | nodo6 (32-37): VM I, VL I
%  nodo7 (38-43): tibia I | nodo8 (44-49): BF I
col.GM_D = 2;  col.VM_D = 8;  col.VL_D = 9;  col.BF_D = 14;
col.GM_I = 20; col.VM_I = 32; col.VL_I = 33; col.BF_I = 44;
col.qS1 = 4:7;   % pelvis derecha
col.qS2 = 10:13; % muslo derecho
col.qS4 = 22:25; % pelvis izquierda
col.qS5 = 28:31; % tibia derecha
col.qS6 = 34:37; % muslo izquierdo
col.qS7 = 40:43; % tibia izquierda

vars = {'hipFlexD','hipFlexI','kneeFlexD','kneeFlexI', ...
        'VM_D','VL_D','VM_I','VL_I','GM_D','GM_I','BF_D','BF_I'};

modosValidos = {'inclinacionmuslo','porrepeticionmuslo','porrepeticion','continuo'};
if ~any(strcmp(lower(modoCadera),modosValidos))
    error('modoCadera "%s" no válido. Opciones: inclinacionMuslo, porRepeticionMuslo, porRepeticion, continuo.',modoCadera);
end

%% ============================================================
% 3. MVC (valores por ensayo, ya en uV)
% =============================================================
archivosMVC.GM_D = {'GMD1.csv','GMD2.csv','GMD3.csv'};
archivosMVC.GM_I = {'GMI1.csv','GMI2.csv','GMI3.csv'};
archivosMVC.BF_D = {'ID1.csv','ID2.csv','ID3.csv'};
archivosMVC.BF_I = {'II1.csv','II2.csv','II3.csv'};
archivosMVC.CUAD = {'MVC1.csv','MVC2.csv','MVC3.csv'};

fprintf('\n=== MVC %s ===\n',paciente);
mvc = struct(); mvcOrigen = struct(); mvcInfo = struct();
for j = 1:numel(musculos)
    m = musculos{j};
    if startsWith(m,'VM') || startsWith(m,'VL'), lista = archivosMVC.CUAD; else, lista = archivosMVC.(m); end
    [mvc.(m),mvcInfo.(m)] = calcularMVC(lista,col.(m),FsEMG,fLow,fHigh,ventanaRMS_s,fracMinEnsayoMVC,m);
    mvcOrigen.(m) = "MVC";
end

%% ============================================================
% 4. FASE 1: PROCESAR CADA ARCHIVO
% =============================================================
SIG = {}; filasUni = [];
nomSensor = {'pelvis D','muslo D','tibia D','pelvis I','muslo I','tibia I'};
for ia = 1:numel(archivosTarea)
    archivo = archivosTarea{ia};
    if ~isfile(archivo), warning('No se encuentra %s; se omite.',archivo); continue; end
    fprintf('\n=== Procesando %s ===\n',archivo);
    datos = cargarCSV(archivo);
    if isempty(datos) || size(datos,2) < 49
        warning('%s no tiene 49 columnas numéricas legibles.',archivo); continue;
    end
    tiempo = datos(:,1);
    Fs = 1/median(diff(tiempo),'omitnan');
    fprintf('Muestras=%d, duración=%.2f s, Fs=%.1f Hz\n',size(datos,1),tiempo(end)-tiempo(1),Fs);
    if abs(Fs-FsEMG) > 1
        warning('%s: Fs del archivo (%.1f Hz) distinta de FsEMG (%d Hz). Revisar.',archivo,Fs,FsEMG);
    end

    [~,base] = fileparts(archivo);
    ej = regexprep(base,'\d+[A-Za-z]?$','');

    rmsEMG = struct(); uni = struct();
    for j = 1:numel(musculos)
        m = musculos{j};
        [rmsEMG.(m),uni.(m)] = procesarEMG(datos(:,col.(m)),FsEMG,fLow,fHigh,ventanaRMS_s);
        g = struct('Archivo',string(archivo),'Musculo',string(m),'Unidad_original',string(uni.(m)));
        filasUni = [filasUni; g]; %#ok<AGROW>
    end

    qP_D = limpiarQ(datos(:,col.qS1),Fs,maxHuecoQ_s); qM_D = limpiarQ(datos(:,col.qS2),Fs,maxHuecoQ_s); qT_D = limpiarQ(datos(:,col.qS5),Fs,maxHuecoQ_s);
    qP_I = limpiarQ(datos(:,col.qS4),Fs,maxHuecoQ_s); qM_I = limpiarQ(datos(:,col.qS6),Fs,maxHuecoQ_s); qT_I = limpiarQ(datos(:,col.qS7),Fs,maxHuecoQ_s);

    Qall = {qP_D,qM_D,qT_D,qP_I,qM_I,qT_I};
    pctInvSensor = zeros(1,6);
    for k = 1:6, pctInvSensor(k) = 100*mean(~all(isfinite(Qall{k}),2)); end
    if any(pctInvSensor > 1)
        fprintf('  %% no válido por sensor (pelvis D, muslo D, tibia D, pelvis I, muslo I, tibia I): %s\n', ...
            sprintf('%.1f ',pctInvSensor));
    end

    restD = detectarReposo({qP_D,qM_D,qT_D},Fs,ventanaReposo_s,busquedaReposo_s);
    restI = detectarReposo({qP_I,qM_I,qT_I},Fs,ventanaReposo_s,busquedaReposo_s);
    if isKey(reposoManual,archivo)
        rc = reposoManual(archivo);
        restD = tiempo >= rc(1) & tiempo <= rc(2); restI = restD;
        fprintf('  Reposo MANUAL: %.2f - %.2f s\n',rc(1),rc(2));
    end
    wD = ventanaT(tiempo,restD); wI = ventanaT(tiempo,restI);
    fprintf('  Reposo D: %.2f - %.2f s | Reposo I: %.2f - %.2f s\n',wD(1),wD(2),wI(1),wI(2));

    [rv.hipD,Qh.D] = rotvecRel(qP_D,qM_D,restD);  [rv.hipI,Qh.I] = rotvecRel(qP_I,qM_I,restI);
    rv.kneeD = rotvecRel(qM_D,qT_D,restD);        rv.kneeI = rotvecRel(qM_I,qT_I,restI);

    % orientacion ABSOLUTA de cada muslo (para la cadera sin pelvis)
    Qm.D = quaternion(qM_D(:,1),qM_D(:,2),qM_D(:,3),qM_D(:,4));
    Qm.I = quaternion(qM_I(:,1),qM_I(:,2),qM_I(:,3),qM_I(:,4));

    sig = struct('archivo',archivo,'base',base,'ejercicio',ej,'t',tiempo,'Fs',Fs);
    sig.rms = rmsEMG; sig.rv = rv; sig.restD = restD; sig.restI = restI; sig.pctInvSensor = pctInvSensor;
    sig.Qs = Qall; sig.Qh = Qh; sig.Qm = Qm;
    SIG{end+1} = sig; %#ok<SAGROW>
end
if isempty(SIG), error('No se ha procesado ningún archivo.'); end
writetable(struct2table(filasUni),[paciente '_unidades_EMG_originales.csv']);

%% ============================================================
% 5. EJES DE FLEXO-EXTENSION (SVD) - GLOBAL y POR ARCHIVO
% =============================================================
fprintf('\n=== Ejes de flexo-extensión ===\n');
jn = {'hipD','hipI','kneeD','kneeI'};
eje = struct(); varExpl = struct(); filasEje = [];
for j = 1:numel(jn)
    X = []; Xs = [];
    for is = 1:numel(SIG)
        r = SIG{is}.rv.(jn{j});
        r = r(all(isfinite(r),2) & sqrt(sum(r.^2,2)) > 5,:);
        r = r(1:10:end,:);
        X = [X; r]; %#ok<AGROW>
        if strcmp(SIG{is}.ejercicio,'S'), Xs = [Xs; r]; end %#ok<AGROW>
    end
    if size(X,1) < 50, error('Muy pocos datos de movimiento para el eje %s.',jn{j}); end
    [~,S,V] = svd(X,'econ');
    ax = V(:,1);
    expl = S(1,1)^2/sum(diag(S).^2);
    varExpl.(jn{j}) = expl;
    if startsWith(jn{j},'hip') && size(Xs,1) > 50, Xref = Xs; else, Xref = X; end
    P = Xref*ax;
    if prctile(P,99) < -prctile(P,1), ax = -ax; end
    eje.(jn{j}) = ax(:)';
    fprintf('GLOBAL %s: eje=[% .2f % .2f % .2f], varianza explicada=%.0f %%\n',jn{j},ax,100*expl);
    g = struct(); g.Archivo = "GLOBAL"; g.Articulacion = string(jn{j});
    g.ex = ax(1); g.ey = ax(2); g.ez = ax(3); g.VarExplicada = expl;
    g.CosConGlobal = 1; g.SignoAmbiguo = false;
    filasEje = [filasEje; g]; %#ok<AGROW>
end

% (los avisos de la cadera pelvis->muslo solo importan si ese modo se usa)
caderaPorEje = any(strcmp(lower(modoCadera),{'porrepeticion','continuo'}));
ejeArch = cell(numel(SIG),1);
for is = 1:numel(SIG)
    ejeArch{is} = struct();
    for j = 1:numel(jn)
        r = SIG{is}.rv.(jn{j});
        r = r(all(isfinite(r),2) & sqrt(sum(r.^2,2)) > 5,:);
        r = r(1:10:end,:);
        axg = eje.(jn{j}); expl = NaN; amb = false; a99 = NaN; a1 = NaN;
        if ejePorArchivo && size(r,1) >= 30
            [~,S,V] = svd(r,'econ');
            ax = V(:,1)'; expl = S(1,1)^2/sum(diag(S).^2);
            P = r*ax';
            a99 = prctile(P,99); a1 = -prctile(P,1);
            if a99 < a1, ax = -ax; t0 = a99; a99 = a1; a1 = t0; end
            amb = min(a99,a1) > 0.6*max(a99,a1);
            avisar = ~startsWith(jn{j},'hip') || caderaPorEje;
            if avisar
                if expl < umbralEje
                    warning('%s %s: solo %.0f %% de la rotación va en un eje (revisar sensores/huecos).', ...
                        SIG{is}.archivo,jn{j},100*expl);
                end
                if amb
                    warning('%s %s: signo AMBIGUO (excursión +%.0f° / -%.0f°). Revisa la gráfica.', ...
                        SIG{is}.archivo,jn{j},a99,a1);
                end
            end
        else
            ax = axg;
            if size(r,1) >= 20
                [~,S,~] = svd(r,'econ'); expl = S(1,1)^2/sum(diag(S).^2);
            end
        end
        ejeArch{is}.(jn{j}) = ax;
        dotG = abs(dot(ax,axg));
        fprintf('%-8s %-6s eje=[% .2f % .2f % .2f] var=%3.0f %% |cos con global|=%.2f\n', ...
            SIG{is}.archivo,jn{j},ax,100*expl,dotG);
        g = struct(); g.Archivo = string(SIG{is}.archivo); g.Articulacion = string(jn{j});
        g.ex = ax(1); g.ey = ax(2); g.ez = ax(3); g.VarExplicada = expl;
        g.CosConGlobal = dotG; g.SignoAmbiguo = amb;
        filasEje = [filasEje; g]; %#ok<AGROW>
    end
end
tablaEjes = struct2table(filasEje);
writetable(tablaEjes,[paciente '_ejes_articulares.csv']);

%% ============================================================
% 6. ANGULOS + INTERVALO ACTIVO
% =============================================================
cfgH = struct('maxAng',maxAnguloCadera_deg,'maxSalto',maxSaltoAngulo_deg,'margen',margenSalto_s, ...
              'ventBase',ventanaBase_s,'maxBase',maxBaseCadera_deg);
fprintf('\n=== Ángulos (cadera en modo "%s") ===\n',modoCadera);
for is = 1:numel(SIG)
    s = SIG{is}; Fs = s.Fs;
    nSmooth = max(1,round(0.05*Fs));
    ang = struct(); infoH = struct();

    % --- rodillas: eje y signo por archivo
    for j = 3:4
        if endsWith(jn{j},'D'), rr = s.restD; else, rr = s.restI; end
        a = s.rv.(jn{j})*ejeArch{is}.(jn{j})';
        a = movmean(a,nSmooth,'omitnan');
        off = median(a(rr),'omitnan'); if ~isfinite(off), off = 0; end
        ang.(jn{j}) = a - off;
    end

    % --- caderas
    modoFile = lower(modoCadera);
    s.etqCadera = 'Cadera flex-ext';
    usadoInc = false;
    if strcmp(modoFile,'inclinacionmuslo')
        infoInc = struct('ok',false,'msg','');
        try
            mov = abs(ang.kneeD) > umbralMovimiento_deg | abs(ang.kneeI) > umbralMovimiento_deg;
            mov(isnan(mov)) = false;
            [inc,infoInc] = inclinacionMuslos(s.Qs{2},s.restD,s.Qs{5},s.restI,mov(:),cfgInc);
        catch ME
            infoInc.ok = false; infoInc.msg = ME.message;
        end
        if infoInc.ok
            usadoInc = true;
            ang.hipD = movmean(inc.D,nSmooth,'omitnan');
            ang.hipI = movmean(inc.I,nSmooth,'omitnan');
            ang.hipD(abs(ang.hipD) > maxAnguloCadera_deg) = NaN;
            ang.hipI(abs(ang.hipI) > maxAnguloCadera_deg) = NaN;
            s.etqCadera = 'Cadera flex-ext (inclinación del muslo)';
            infoH.hipD = struct('glitches',0,'pctSalto',0,'pctRango',0,'pctBase',0,'pctValido',100*mean(isfinite(ang.hipD)));
            infoH.hipI = struct('glitches',0,'pctSalto',0,'pctRango',0,'pctBase',0,'pctValido',100*mean(isfinite(ang.hipI)));
            fprintf(['%s: cadera = inclinación sagital del muslo (marco %s, eje %d, |z| en reposo %.2f, ' ...
                     'consistencia de dirección %.2f) | válida D=%.0f %%, I=%.0f %% | inclinación máx D=%.0f°, I=%.0f°\n'], ...
                s.archivo,infoInc.conv,infoInc.eje,infoInc.vert,infoInc.consist, ...
                infoH.hipD.pctValido,infoH.hipI.pctValido,infoInc.tiltMax(1),infoInc.tiltMax(2));
        else
            warning(['%s: no se pudo usar la inclinación del muslo (%s). ' ...
                     'Se usa la cadera por repetición con el muslo (sin pelvis).'],s.archivo,infoInc.msg);
            modoFile = 'porrepeticionmuslo';
        end
    end
    if ~usadoInc
        for j = 1:2
            if j == 1, rr = s.restD; else, rr = s.restI; end
            [ang.(jn{j}),~,infoH.(jn{j})] = anguloContinuo(s.rv.(jn{j}),ejeArch{is}.(jn{j}),Fs,rr,cfgH);
        end
        fprintf('%s: cadera continua (referencia) válida D=%.0f %% (glitches %d) | I=%.0f %% (glitches %d)\n', ...
            s.archivo,infoH.hipD.pctValido,infoH.hipD.glitches,infoH.hipI.pctValido,infoH.hipI.glitches);
    end
    s.modoCaderaUsado = modoFile;
    s.hipFlexD = ang.hipD; s.hipFlexI = ang.hipI;
    s.infoHip  = struct('D',infoH.hipD,'I',infoH.hipI);
    s.kneeFlexD = ang.kneeD; s.kneeFlexI = ang.kneeI;
    s = rmfield(s,'rv');

    % --- desfase izquierda-derecha
    s.lagIzq = lagIzqVsDer(s.kneeFlexD,s.kneeFlexI,Fs,maxLagLados_s);
    s.lagBruto = s.lagIzq;                       % se conserva para el CSV de calidad
    s.alineado = false;
    fracD = mean(isfinite(s.kneeFlexD)); fracI = mean(isfinite(s.kneeFlexI));
    fprintf('%s: lag rodilla I vs D = %+.2f s (>0 = izquierda retrasada) | datos válidos D=%.0f %%, I=%.0f %%\n', ...
        s.archivo,s.lagIzq,100*fracD,100*fracI);
    if alinearLados && any(strcmp(s.ejercicio,ejerciciosSimetricos))
        c0 = corrDI(s.kneeFlexD,s.kneeFlexI);
        desf = @(y) interp1(s.t,y,s.t + s.lagIzq,'linear',NaN);
        c1 = corrDI(s.kneeFlexD,desf(s.kneeFlexI));
        if min(fracD,fracI) < umbralValidezAlinear
            warning('%s: pocos datos válidos en un lado; NO se alinea.',s.archivo); s.lagIzq = 0;
        elseif abs(s.lagIzq) < minLagCorregir_s
            fprintf('   -> lag < %.2f s: no se corrige\n',minLagCorregir_s); s.lagIzq = 0;
        elseif ~(c1 > c0 + minMejoraCorr)
            fprintf('   -> alinear no mejora la coincidencia D-I (%.2f -> %.2f): NO se corrige\n',c0,c1); s.lagIzq = 0;
        else
            s.hipFlexI = desf(s.hipFlexI); s.kneeFlexI = desf(s.kneeFlexI);
            for mm = {'VM_I','VL_I','GM_I','BF_I'}, s.rms.(mm{1}) = desf(s.rms.(mm{1})); end
            s.alineado = true;
            fprintf('   -> señal izquierda alineada con la derecha (%+.2f s; correlación D-I %.2f -> %.2f)\n',s.lagIzq,c0,c1);
        end
    end

    mx = max(abs([s.hipFlexD; s.hipFlexI; s.kneeFlexD; s.kneeFlexI]),[],'omitnan');
    if mx > 180, warning('%s: ángulo > 180° (%.0f°). Revisar sensores.',s.archivo,mx); end

    active = abs(s.kneeFlexD) > umbralMovimiento_deg | abs(s.kneeFlexI) > umbralMovimiento_deg;
    active(isnan(active)) = false;
    active = rellenarHuecos(active,round(rellenoHuecos_s*Fs));
    active = quitarTramosCortos(active,round(duracionMinMovimiento_s*Fs));
    if any(active), ii = find(active); s.iStart = ii(1); s.iEnd = ii(end);
    else, warning('No se detectó intervalo activo en %s.',s.archivo); s.iStart = 1; s.iEnd = numel(s.t); end
    if isKey(recorteManual,s.archivo)
        rc = recorteManual(s.archivo);
        s.iStart = find(s.t >= rc(1),1,'first'); s.iEnd = find(s.t <= rc(2),1,'last');
        fprintf('%s: recorte manual %.1f - %.1f s\n',s.archivo,rc(1),rc(2));
    end
    ii = s.iStart:s.iEnd;
    s.pctValido = 100*[mean(isfinite(s.hipFlexD(ii))) mean(isfinite(s.hipFlexI(ii))) ...
                       mean(isfinite(s.kneeFlexD(ii))) mean(isfinite(s.kneeFlexI(ii)))];
    SIG{is} = s;
end

%% ============================================================
% 7. MVC DEFINITIVO Y %MVC
% =============================================================
fprintf('\n=== Validación del MVC frente a las tareas ===\n');
for j = 1:numel(musculos)
    m = musculos{j};
    picoTarea = 0;
    for is = 1:numel(SIG), picoTarea = max(picoTarea,prctile(SIG{is}.rms.(m),99.9)); end
    if isfield(mvcManual,m) && ~isempty(mvcManual.(m))
        fprintf('MVC %s sustituido manualmente: %.5g -> %.5g\n',m,mvc.(m),mvcManual.(m));
        mvc.(m) = mvcManual.(m); mvcOrigen.(m) = "Manual";
    elseif ~isfinite(mvc.(m)) || mvc.(m) < fracMinMVCvsTarea*picoTarea
        warning(['%s: MVC (%.4g) incompatible con la escala de la tarea (pico %.4g). ' ...
                 'Se normaliza al PICO DE LA TAREA: NO es %%MVC real.'],nombreMusculo(m),mvc.(m),picoTarea);
        mvc.(m) = picoTarea; mvcOrigen.(m) = "PICO TAREA (MVC inválido)";
    end
end

tablaMVC = table(string(musculos(:)),cellfun(@(m) string(nombreMusculo(m)),musculos(:)), ...
    cellfun(@(m) mvc.(m),musculos(:)),cellfun(@(m) mvcOrigen.(m),musculos(:)), ...
    cellfun(@(m) mvcInfo.(m).nValidos,musculos(:)),cellfun(@(m) mvcInfo.(m).ratio,musculos(:)), ...
    'VariableNames',{'Codigo','Musculo','MVC_RMS_uV','Origen','N_ensayos_validos','Ratio_max_min'});
disp(tablaMVC); writetable(tablaMVC,[paciente '_valores_MVC.csv']);

for is = 1:numel(SIG)
    s = SIG{is};
    for j = 1:numel(musculos)
        m = musculos{j}; s.(m) = 100*s.rms.(m)/mvc.(m);
    end
    t = s.t;
    Tout = table(t,s.hipFlexD,s.hipFlexI,s.kneeFlexD,s.kneeFlexI,s.GM_D,s.GM_I,s.VM_D,s.VL_D, ...
        s.VM_I,s.VL_I,s.BF_D,s.BF_I,'VariableNames',{'Tiempo_s','Cadera_Flex_D','Cadera_Flex_I', ...
        'Rodilla_Flex_D','Rodilla_Flex_I','GM_D_pctMVC','GM_I_pctMVC','VM_D_pctMVC','VL_D_pctMVC', ...
        'VM_I_pctMVC','VL_I_pctMVC','BF_D_pctMVC','BF_I_pctMVC'});
    writetable(Tout,[s.base '_' paciente '_senales_procesadas.csv']);
    SIG{is} = s;

    if figurasPorArchivo
        f = nuevaFigura(['Revisión - ' s.archivo],[100 50 1000 800]);
        tiledlayout(f,2,1,'TileSpacing','compact');
        nexttile; hold on; h1 = plot(t,s.hipFlexD,'LineWidth',1.2); h2 = plot(t,s.hipFlexI,'LineWidth',1.2);
        if any(s.restD), xregion(t(find(s.restD,1,'first')),t(find(s.restD,1,'last'))); end
        yline(0,':k'); grid on;
        xline([t(s.iStart) t(s.iEnd)],'--k'); ylabel('Grados'); title(s.etqCadera);
        legend([h1 h2],{'Derecha','Izquierda'},'Location','best');
        nexttile; hold on; h1 = plot(t,s.kneeFlexD,'LineWidth',1.2); h2 = plot(t,s.kneeFlexI,'LineWidth',1.2);
        if any(s.restD), xregion(t(find(s.restD,1,'first')),t(find(s.restD,1,'last'))); end
        yline(0,':k'); grid on;
        xline([t(s.iStart) t(s.iEnd)],'--k'); ylabel('Grados'); xlabel('Tiempo (s)'); title('Rodilla flex-ext');
        legend([h1 h2],{'Derecha','Izquierda'},'Location','best');
        sgtitle([s.archivo ' - zona sombreada = reposo de calibración (derecha)']);
        guardarYMostrar(f,fullfile(carpetaFiguras,[s.base '_revision.png']),mostrarFigurasEnPantalla);
    end
end

%% ============================================================
% 8. FASE 2: SEGMENTAR REPETICIONES Y NORMALIZAR EN TIEMPO
% =============================================================
ACUM = struct(); filas = [];
for is = 1:numel(SIG)
    s = SIG{is}; ej = s.ejercicio;
    if isKey(modoSegmentacion,ej), modo = modoSegmentacion(ej); else, modo = 'ambas'; end
    % [v3.2] 'VLI' anadido; un modo desconocido da error (antes caia en 'ambas' sin avisar)
    switch modo
        case 'D',     xSeg = s.kneeFlexD;
        case 'I',     xSeg = s.kneeFlexI;
        case 'HD',    xSeg = s.hipFlexD;
        case 'HI',    xSeg = s.hipFlexI;
        case 'VLD',   xSeg = s.VL_D;
        case 'VLI',   xSeg = s.VL_I;
        case 'ambas', xSeg = mean([s.kneeFlexD s.kneeFlexI],2,'omitnan');
        otherwise,    error('modoSegmentacion "%s" no válido (archivo %s).',modo,s.archivo);
    end
    % [v3.2] 'centrado' y la prominencia EMG se definen aqui, ANTES de usarse, para VLD y VLI
    centrado = any(strcmp(modo,{'VLD','VLI'}));
    if centrado, promUse = promMinVLD_pct; fracUse = fracPromVLD;
    else, promUse = prominenciaMin_deg; fracUse = fraccionProminencia; end
    if isKey(distanciaMinPicosEj,ej), dmin = distanciaMinPicosEj(ej); else, dmin = distanciaMinPicos_s; end
    if isKey(padFinalSeg_s,ej), padS = round(padFinalSeg_s(ej)*s.Fs); else, padS = 0; end
    iEndSeg = min(numel(s.t),s.iEnd + padS);
    reps = segmentarRepeticiones(xSeg,s.iStart,iEndSeg,s.Fs,dmin,promUse, ...
        fracUse,incluirRepIncompleta,centrado,tolCentrado);
    msgFrag = '';
    if size(reps,1) >= 2
        durR = (s.t(reps(:,2)) - s.t(reps(:,1)));
        frag = durR < fracDurMinRep*median(durR);
        if any(frag)
            msgFrag = sprintf('   DESCARTADAS %d repeticion(es) < %.0f %% de la mediana (%.2f s): %s s\n',nnz(frag), ...
                100*fracDurMinRep,median(durR),mat2str(round(durR(frag)',2)));
            reps(frag,:) = [];
        end
    end
    msgEx = '';
    if isKey(excluirVentana,s.archivo) && ~isempty(reps)
        wEx = excluirVentana(s.archivo);
        tm = (s.t(reps(:,1)) + s.t(reps(:,2)))/2;     % instante central de cada repeticion
        malas = tm >= wEx(1) & tm <= wEx(2);
        msgEx = sprintf('   EXCLUIDAS %d repeticion(es) de %s en la ventana %.1f-%.1f s\n',nnz(malas),s.archivo,wEx(1),wEx(2));
        reps(malas,:) = [];
    end
    % [v3.2] el recuento se imprime DESPUES de descartar fragmentos y excluir ventanas
    if centrado, txtCentr = ', centrada en el pico'; else, txtCentr = ''; end
    fprintf('%s (%s, segmentación "%s"%s): %d repeticiones válidas\n',s.archivo,nombreDe(nombreEjercicio,ej),modo, ...
        txtCentr,size(reps,1));
    if ~isempty(msgFrag), fprintf('%s',msgFrag); end
    if ~isempty(msgEx),   fprintf('%s',msgEx);   end
    for rr = 1:size(reps,1)
        fprintf('   rep %d: %6.2f - %6.2f s (%.2f s)\n',rr,s.t(reps(rr,1)),s.t(reps(rr,2)), ...
            s.t(reps(rr,2))-s.t(reps(rr,1)));
    end
    SIG{is}.reps = reps;

    % cadera: segun el modo realmente usado en ESTE archivo
    modoCad = s.modoCaderaUsado;
    useRep  = any(strcmp(modoCad,{'porrepeticion','porrepeticionmuslo'}));
    if strcmp(modoCad,'porrepeticion'), QhD = s.Qh.D; QhI = s.Qh.I; else, QhD = s.Qm.D; QhI = s.Qm.I; end
    hipD_c = NaN(numel(s.t),1); hipI_c = NaN(numel(s.t),1);
    lagS = 0; if s.alineado, lagS = round(s.lagIzq*s.Fs); end
    nHD = 0; nHI = 0;

    for r = 1:size(reps,1)
        ia = reps(r,1); ib = reps(r,2);
        tr = s.t(ia:ib); tn = linspace(tr(1),tr(end),nPuntos);
        okD = mean(~isfinite(s.kneeFlexD(ia:ib))) <= 0.05;
        okI = mean(~isfinite(s.kneeFlexI(ia:ib))) <= 0.05;
        if emgIndependienteCinematica, okED = true; okEI = true; else, okED = okD; okEI = okI; end

        eHD = NaN; eHI = NaN;
        if useRep
            [aHD,hOkD,eHD] = anguloRepRelativo(QhD,ia,ib,s.Fs,minExplCadera,maxAnguloCadera_deg,cierreRepCadera_deg);
            [aHI,hOkI,eHI] = anguloRepRelativo(QhI,ia+lagS,ib+lagS,s.Fs,minExplCadera,maxAnguloCadera_deg,cierreRepCadera_deg);
        else
            aHD = s.hipFlexD(ia:ib); aHI = s.hipFlexI(ia:ib);
            if strcmp(modoCad,'inclinacionmuslo')
                % sin condicion de cierre: la inclinacion es absoluta, no relativa al inicio
                hOkD = mean(isfinite(aHD)) >= 0.95 && max(abs(aHD)) <= maxAnguloCadera_deg;
                hOkI = mean(isfinite(aHI)) >= 0.95 && max(abs(aHI)) <= maxAnguloCadera_deg;
            else
                hOkD = repCaderaValida(aHD,cierreRepCadera_deg,maxAnguloCadera_deg);
                hOkI = repCaderaValida(aHI,cierreRepCadera_deg,maxAnguloCadera_deg);
            end
        end
        hOkD = hOkD && okD; hOkI = hOkI && okI;
        if hOkD, hipD_c(ia:ib) = aHD; nHD = nHD + 1; end
        if hOkI, hipI_c(ia:ib) = aHI; nHI = nHI + 1; end

        for v = 1:numel(vars)
            switch vars{v}
                case 'hipFlexD', yv = aHD; bad = ~hOkD;
                case 'hipFlexI', yv = aHI; bad = ~hOkI;
                case {'kneeFlexD'}, yv = s.(vars{v})(ia:ib); bad = ~okD;
                case {'kneeFlexI'}, yv = s.(vars{v})(ia:ib); bad = ~okI;
                otherwise
                    yv = s.(vars{v})(ia:ib);
                    bad = (endsWith(vars{v},'D') && ~okED) || (endsWith(vars{v},'I') && ~okEI);
            end
            if bad, yv = NaN(size(yv)); end
            yn = interp1(tr,yv,tn,'linear');
            if ~isfield(ACUM,ej) || ~isfield(ACUM.(ej),vars{v}), ACUM.(ej).(vars{v}) = yn;
            else, ACUM.(ej).(vars{v}) = [ACUM.(ej).(vars{v}); yn]; end
        end
        f = struct();
        f.Ejercicio = string(ej); f.Archivo = string(s.archivo); f.Rep = r; f.Duracion_s = tr(end)-tr(1);
        f.ROM_Cadera_D = NaN; f.ROM_Cadera_I = NaN; f.ROM_Rodilla_D = NaN; f.ROM_Rodilla_I = NaN;
        if okD, f.ROM_Rodilla_D = rangoSeguro(s.kneeFlexD(ia:ib)); end
        if okI, f.ROM_Rodilla_I = rangoSeguro(s.kneeFlexI(ia:ib)); end
        if hOkD, f.ROM_Cadera_D = rangoSeguro(aHD); end
        if hOkI, f.ROM_Cadera_I = rangoSeguro(aHI); end
        if isKey(excluirROM,s.archivo)
            exj = excluirROM(s.archivo);
            if any(strcmp(exj,'hipD')),  f.ROM_Cadera_D  = NaN; end
            if any(strcmp(exj,'hipI')),  f.ROM_Cadera_I  = NaN; end
            if any(strcmp(exj,'kneeD')), f.ROM_Rodilla_D = NaN; end
            if any(strcmp(exj,'kneeI')), f.ROM_Rodilla_I = NaN; end
        end
        f.CaderaValida_D = hOkD; f.CaderaValida_I = hOkI;
        f.ExplCadera_D = eHD;    f.ExplCadera_I = eHI;
        for j = 1:numel(musculos)
            m = musculos{j}; y = s.(m)(ia:ib);
            if (endsWith(m,'D') && ~okED) || (endsWith(m,'I') && ~okEI), y(:) = NaN; end
            f.(['Media_' m '_pctMVC'])      = mean(y,'omitnan');
            f.(['Pico_' m '_pctMVC'])       = max(y,[],'omitnan');
            if all(isnan(y)), f.(['Integral_' m '_pctMVC_s']) = NaN;
            else, f.(['Integral_' m '_pctMVC_s']) = trapz(tr,fillmissing(y,'constant',0)); end
        end
        filas = [filas; f]; %#ok<AGROW>
    end
    if useRep      % en los modos por repeticion se dibuja solo la cadera de las repeticiones validas
        SIG{is}.hipFlexD = hipD_c; SIG{is}.hipFlexI = hipI_c;
    end
    fprintf('   cadera válida: D %d/%d repeticiones | I %d/%d repeticiones\n',nHD,size(reps,1),nHI,size(reps,1));
end
if isempty(filas), error('No se detectó ninguna repetición.'); end

T = struct2table(filas);
T.NombreEjercicio = arrayfun(@(e) string(nombreDe(nombreEjercicio,char(e))),T.Ejercicio);
writetable(T,[paciente '_metricas_por_repeticion.csv']);
ejs = fieldnames(ACUM);
nomEj = cellfun(@(e) nombreDe(nombreEjercicio,e),ejs,'UniformOutput',false);

filasQcad = [];
for is = 1:numel(SIG)
    s = SIG{is}; sel = T.Archivo == string(s.archivo);
    g = struct();
    g.Archivo = string(s.archivo); g.ModoCadera = string(s.modoCaderaUsado); g.Repeticiones = nnz(sel);
    g.RepsCaderaValida_D = nnz(sel & T.CaderaValida_D); g.RepsCaderaValida_I = nnz(sel & T.CaderaValida_I);
    g.ExplCadera_D_mediana = median(T.ExplCadera_D(sel),'omitnan');
    g.ExplCadera_I_mediana = median(T.ExplCadera_I(sel),'omitnan');
    g.PctSenalValida_D = s.infoHip.D.pctValido; g.PctSenalValida_I = s.infoHip.I.pctValido;
    filasQcad = [filasQcad; g]; %#ok<AGROW>
end
tablaQcad = struct2table(filasQcad);
writetable(tablaQcad,[paciente '_calidad_cadera.csv']);
disp('CALIDAD DE LA CADERA POR ARCHIVO:'); disp(tablaQcad);

%% ============================================================
% 9. TABLAS: EMG, ROM, SIMETRIA, CALIDAD
% =============================================================
filasEMG = [];
for ie = 1:numel(ejs)
    sel = T.Ejercicio == string(ejs{ie});
    for j = 1:numel(musculos)
        m = musculos{j};
        media = T.(['Media_' m '_pctMVC'])(sel); pico = T.(['Pico_' m '_pctMVC'])(sel);
        integ = T.(['Integral_' m '_pctMVC_s'])(sel);
        g = struct();
        g.Ejercicio = string(nomEj{ie}); g.Musculo = string(nombreMusculo(m));
        g.MVC_RMS = mvc.(m); g.Origen_MVC = mvcOrigen.(m); g.N_repeticiones = nnz(sel); g.N_validas = nnz(isfinite(pico));
        g.Media_pctMVC = mean(media,'omitnan'); g.SD_Media_pctMVC = std(media,'omitnan');
        g.Pico_pctMVC = mean(pico,'omitnan');   g.SD_Pico_pctMVC = std(pico,'omitnan');
        g.Integral_pctMVC_s = mean(integ,'omitnan');
        filasEMG = [filasEMG; g]; %#ok<AGROW>
    end
end
tablaEMG = struct2table(filasEMG);
writetable(tablaEMG,[paciente '_resultados_EMG_pctMVC.csv']);
disp('RESULTADOS EMG (%MVC) POR EJERCICIO Y MÚSCULO:'); disp(tablaEMG);

filasROM = [];
for ie = 1:numel(ejs)
    sel = T.Ejercicio == string(ejs{ie});
    g = struct(); g.Ejercicio = string(nomEj{ie}); g.N_repeticiones = nnz(sel);
    g.Duracion_rep_s = mean(T.Duracion_s(sel),'omitnan');
    for art = {'Cadera','Rodilla'}
        for lado = {'D','I'}
            v = T.(['ROM_' art{1} '_' lado{1}])(sel);
            g.(['ROM_' art{1} '_' lado{1} '_media_deg']) = mean(v,'omitnan');
            g.(['ROM_' art{1} '_' lado{1} '_SD_deg'])    = std(v,'omitnan');
            g.(['N_' art{1} '_' lado{1}])                = nnz(isfinite(v));
        end
    end
    filasROM = [filasROM; g]; %#ok<AGROW>
end
tablaROM = struct2table(filasROM);
writetable(tablaROM,[paciente '_resultados_ROM.csv']);
disp('RANGO DE MOVIMIENTO (flex-ext) POR EJERCICIO:'); disp(tablaROM);

filasSim = [];
for ie = 1:numel(ejs)
    sel = T.Ejercicio == string(ejs{ie});
    for ib = 1:numel(paresBase)
        b = paresBase{ib};
        for tipo = {'Pico','Media'}
            d = mean(T.([tipo{1} '_' b '_D_pctMVC'])(sel),'omitnan');
            iz = mean(T.([tipo{1} '_' b '_I_pctMVC'])(sel),'omitnan');
            g = struct(); g.Ejercicio = string(nomEj{ie});
            g.Variable = string([tipo{1} ' %MVC - ' nombreBase{ib}]);
            g.Derecha = d; g.Izquierda = iz; g.IndiceSimetria_pct = 100*(d-iz)/((d+iz)/2);
            filasSim = [filasSim; g]; %#ok<AGROW>
        end
    end
    for art = {'Cadera','Rodilla'}
        d = mean(T.(['ROM_' art{1} '_D'])(sel),'omitnan'); iz = mean(T.(['ROM_' art{1} '_I'])(sel),'omitnan');
        g = struct(); g.Ejercicio = string(nomEj{ie}); g.Variable = string(['ROM ' art{1} ' (grados)']);
        g.Derecha = d; g.Izquierda = iz; g.IndiceSimetria_pct = 100*(d-iz)/((d+iz)/2);
        filasSim = [filasSim; g]; %#ok<AGROW>
    end
end
tablaSim = struct2table(filasSim);
writetable(tablaSim,[paciente '_comparacion_lados.csv']);
disp('COMPARACIÓN DERECHA vs IZQUIERDA:'); disp(tablaSim);

archivosSIG = cellfun(@(q) q.archivo,SIG,'UniformOutput',false);
nM = numel(musculos);
picoMax = zeros(nM,1); nSobre100 = zeros(nM,1); aviso = strings(nM,1);
for j = 1:nM
    m = musculos{j};
    p = T.(['Pico_' m '_pctMVC']);
    picoMax(j) = max(p,[],'omitnan'); nSobre100(j) = nnz(p > 100);
    pf = cellfun(@(q) prctile(q.(m),99),SIG);
    apag = pf < 2;
    if mvcOrigen.(m) == "PICO TAREA (MVC inválido)"
        aviso(j) = "MVC inválido: valores relativos al pico de la tarea, NO %MVC real. Repetir/revisar MVC";
    elseif any(apag) && any(pf > 20)
        aviso(j) = "Canal casi plano SOLO en: " + string(strjoin(archivosSIG(apag),', ')) + " (¿electrodo desconectado?)";
    elseif picoMax(j) < 5,   aviso(j) = "Casi plano: revisar canal";
    elseif picoMax(j) < 15,  aviso(j) = "Pico < 15 %MVC en todas las tareas: MVC posiblemente inflado (artefacto) o poca señal";
    elseif picoMax(j) > 120, aviso(j) = "Supera su MVC: posible MVC infravalorado";
    else, aviso(j) = "OK"; end
end
tablaQC = table(cellfun(@(m) string(nombreMusculo(m)),musculos(:)),cellfun(@(m) mvc.(m),musculos(:)), ...
    cellfun(@(m) mvcOrigen.(m),musculos(:)),picoMax,nSobre100,aviso, ...
    'VariableNames',{'Musculo','MVC_RMS_uV','Origen_MVC','PicoMax_pctMVC','Reps_pico_mayor_100','Aviso'});
writetable(tablaQC,[paciente '_control_calidad_EMG.csv']);
disp('CONTROL DE CALIDAD EMG:'); disp(tablaQC);

% Calidad cinematica por archivo
filasCin = [];
for is = 1:numel(SIG)
    s = SIG{is}; g = struct(); g.Archivo = string(s.archivo);
    g.ModoCadera = string(s.modoCaderaUsado);
    g.pctInv_PelvisD = s.pctInvSensor(1); g.pctInv_MusloD = s.pctInvSensor(2); g.pctInv_TibiaD = s.pctInvSensor(3);
    g.pctInv_PelvisI = s.pctInvSensor(4); g.pctInv_MusloI = s.pctInvSensor(5); g.pctInv_TibiaI = s.pctInvSensor(6);
    g.pctValido_CaderaD = s.pctValido(1); g.pctValido_CaderaI = s.pctValido(2);
    g.pctValido_RodillaD = s.pctValido(3); g.pctValido_RodillaI = s.pctValido(4);
    g.Lag_I_vs_D_s = s.lagIzq;
    g.Lag_bruto_s = s.lagBruto;   % lag calculado, aunque no se haya aplicado
    g.Reposo_D_inicio_s = s.t(find(s.restD,1,'first')); g.Reposo_I_inicio_s = s.t(find(s.restI,1,'first'));
    filasCin = [filasCin; g]; %#ok<AGROW>
end
writetable(struct2table(filasCin),[paciente '_calidad_cinematica_por_archivo.csv']);

%% ============================================================
% 10A. MOVIMIENTO REAL POR EJERCICIO (4 filas x n series)
% =============================================================
if figurasMovimientoReal
    for ie = 1:numel(ejs)
        idxSer = find(cellfun(@(q) strcmp(q.ejercicio,ejs{ie}),SIG));
        nS = numel(idxSer);
        figR = nuevaFigura(['Movimiento real - ' nomEj{ie}],[50 50 min(1800,560*nS) 1050]);
        tl = tiledlayout(figR,4,nS,'TileSpacing','compact');
        axR = gobjects(4,nS);
        for r = 1:4
            for k = 1:nS
                q = SIG{idxSer(k)};
                axR(r,k) = nexttile(tl); hold on;
                switch r
                    case 1
                        h = [plot(q.t,q.hipFlexD,'LineWidth',1.2) plot(q.t,q.hipFlexI,'LineWidth',1.2)];
                        etq = {'Derecha','Izquierda'}; ylab = 'Grados';
                        if q.alineado, txtAl = ', alineada'; else, txtAl = ''; end
                        title(sprintf('%s - %s (lag I = %+.2f s%s)',q.archivo,q.etqCadera,q.lagBruto,txtAl));
                    case 2
                        h = [plot(q.t,q.kneeFlexD,'LineWidth',1.2) plot(q.t,q.kneeFlexI,'LineWidth',1.2)];
                        etq = {'Derecha','Izquierda'}; title('Rodilla flex-ext'); ylab = 'Grados';
                    case 3
                        h = [plot(q.t,q.VM_D) plot(q.t,q.VL_D) plot(q.t,q.VM_I) plot(q.t,q.VL_I)];
                        etq = {'VM D','VL D','VM I','VL I'}; title('Cuádriceps (%MVC)'); ylab = '%MVC';
                    case 4
                        h = [plot(q.t,q.GM_D) plot(q.t,q.GM_I) plot(q.t,q.BF_D) plot(q.t,q.BF_I)];
                        etq = {'GM D','GM I','Isquio D','Isquio I'}; title('Glúteo medio e isquiotibiales (%MVC)');
                        ylab = '%MVC'; xlabel('Tiempo (s)');
                end
                decorarMovimiento(q);
                if k == 1, ylabel(ylab); legend(h,etq,'Location','best'); end
            end
        end
        tIni = min(cellfun(@(q) q.t(1),SIG(idxSer))); tFin = max(cellfun(@(q) q.t(end),SIG(idxSer)));
        set(axR(:),'XLim',[tIni tFin]);
        for r = 1:4
            yl = [inf -inf];
            for k = 1:nS, l = ylim(axR(r,k)); yl = [min(yl(1),l(1)) max(yl(2),l(2))]; end
            set(axR(r,:),'YLim',yl);
        end
        sgtitle(tl,sprintf('%s - %s - movimiento real de cada serie',paciente,nomEj{ie}));
        archivoPNG = fullfile(carpetaFiguras,[paciente '_movimiento_real_' ejs{ie} '.png']);
        guardarYMostrar(figR,archivoPNG,mostrarFigurasEnPantalla);
        fprintf('Movimiento real: %s -> %s\n',nomEj{ie},archivoPNG);
    end
end

%% ============================================================
% 10B. MOVIMIENTO MEDIO POR EJERCICIO
% =============================================================
x = linspace(0,100,nPuntos);
if figurasMediaPorEjercicio
    for ie = 1:numel(ejs)
        A = ACUM.(ejs{ie}); nR = size(A.kneeFlexD,1); c = lines(4);
        nvD = nnz(any(isfinite(A.hipFlexD),2)); nvI = nnz(any(isfinite(A.hipFlexI),2));
        figMov = nuevaFigura(['Movimiento medio - ' nomEj{ie}],[100 50 850 1000]);
        tl = tiledlayout(figMov,4,1,'TileSpacing','compact');
        nexttile(tl); hold on;
        plotBanda(x,A.hipFlexD,c(1,:),'Derecha',true); plotBanda(x,A.hipFlexI,c(2,:),'Izquierda',true);
        grid on; xlim([0 100]); ylabel('Grados'); legend('Location','best');
        title(sprintf('Cadera - flex-ext (n = %d repeticiones; válidas: D = %d, I = %d; grueso = media ± DE, fino = cada repetición)',nR,nvD,nvI));
        nexttile(tl); hold on;
        plotBanda(x,A.kneeFlexD,c(1,:),'Derecha',true); plotBanda(x,A.kneeFlexI,c(2,:),'Izquierda',true);
        grid on; xlim([0 100]); ylabel('Grados'); legend('Location','best'); title('Rodilla - flex-ext');
        nexttile(tl); hold on;
        plotBanda(x,A.VM_D,c(1,:),nombreMusculo('VM_D')); plotBanda(x,A.VL_D,c(2,:),nombreMusculo('VL_D'));
        plotBanda(x,A.VM_I,c(3,:),nombreMusculo('VM_I')); plotBanda(x,A.VL_I,c(4,:),nombreMusculo('VL_I'));
        grid on; xlim([0 100]); ylabel('%MVC'); legend('Location','best'); title('Cuádriceps');
        nexttile(tl); hold on;
        plotBanda(x,A.GM_D,c(1,:),nombreMusculo('GM_D')); plotBanda(x,A.GM_I,c(2,:),nombreMusculo('GM_I'));
        plotBanda(x,A.BF_D,c(3,:),'Isquiotibiales D'); plotBanda(x,A.BF_I,c(4,:),'Isquiotibiales I');
        grid on; xlim([0 100]); xlabel('% del ciclo de repetición'); ylabel('%MVC');
        legend('Location','best'); title('Glúteo medio e isquiotibiales');
        sgtitle(tl,sprintf('%s - %s - movimiento medio de todas las series',paciente,nomEj{ie}));
        archivoPNG = fullfile(carpetaFiguras,[paciente '_movimiento_medio_' ejs{ie} '.png']);
        guardarYMostrar(figMov,archivoPNG,mostrarFigurasEnPantalla);
        fprintf('Movimiento medio: %s -> %s\n',nomEj{ie},archivoPNG);

        M = x(:); nomCol = {'Ciclo_pct'};
        for v = 1:numel(vars)
            M(:,end+1) = mean(A.(vars{v}),1,'omitnan')';  nomCol{end+1} = ['Media_' vars{v}]; %#ok<SAGROW>
            M(:,end+1) = std(A.(vars{v}),0,1,'omitnan')'; nomCol{end+1} = ['SD_' vars{v}];    %#ok<SAGROW>
        end
        writetable(array2table(M,'VariableNames',nomCol),[paciente '_curvas_medias_' ejs{ie} '.csv']);
    end
end

%% ============================================================
% 11. COMPARACION ENTRE EJERCICIOS
% =============================================================
if figurasComparacion
    nombresMusLargos = cellfun(@(m) nombreMusculo(m),musculos,'UniformOutput',false);
    f1 = nuevaFigura('EMG en %MVC por ejercicio',[100 50 1000 800]);
    tl = tiledlayout(f1,2,1,'TileSpacing','compact');
    nexttile(tl); graficoBarrasEMG(T,ejs,nomEj,musculos,nombresMusLargos,'Pico_','Pico (%MVC)', ...
        'Pico de activación por músculo (media ± DE entre repeticiones)');
    nexttile(tl); graficoBarrasEMG(T,ejs,nomEj,musculos,nombresMusLargos,'Media_','Media (%MVC)', ...
        'Activación media por músculo (media ± DE entre repeticiones)');
    sgtitle(tl,sprintf('%s - EMG normalizado respecto al MVC',paciente));
    guardarYMostrar(f1,fullfile(carpetaFiguras,[paciente '_comparacion_EMG.png']),mostrarFigurasEnPantalla);

    f2 = nuevaFigura('Rango de movimiento por ejercicio',[100 50 900 450]);
    tl = tiledlayout(f2,1,2,'TileSpacing','compact');
    nexttile(tl); graficoBarrasLado(T,ejs,nomEj,'ROM_Cadera_D','ROM_Cadera_I','Grados','Cadera (flex-ext)');
    nexttile(tl); graficoBarrasLado(T,ejs,nomEj,'ROM_Rodilla_D','ROM_Rodilla_I','Grados','Rodilla (flex-ext)');
    sgtitle(tl,sprintf('%s - Rango de movimiento por ejercicio',paciente));
    guardarYMostrar(f2,fullfile(carpetaFiguras,[paciente '_comparacion_ROM.png']),mostrarFigurasEnPantalla);
end

%% ============================================================
% 12. RESUMEN PARA LA COMPARACION GLOBAL (pierna operada vs sana)
% =============================================================
% LSI = operada / sana x 100, con las medias de cada variable.
% Sentarse-levantarse: ambas piernas en la misma tarea.
% Subida de escalon: operada en la serie en que ELLA inicia; sana en la serie en que ELLA inicia.
% Si un lado no tiene senal (pico < umbralCanalPlano_pct en todas las repeticiones) -> Calidad 0 y LSI NaN.
ladoSan = setdiff('DI',ladoOperado);
exOp = ['E' ladoOperado]; exSan = ['E' ladoSan];
defs = {};
for b = {'VM','VL','GM','BF'}
    defs(end+1,:) = {['Pico_'  b{1}], ['Pico_'  b{1} '_%s_pctMVC'], b{1}, 'EMG'}; %#ok<SAGROW>
    defs(end+1,:) = {['Media_' b{1}], ['Media_' b{1} '_%s_pctMVC'], b{1}, 'EMG'}; %#ok<SAGROW>
end
defs(end+1,:) = {'ROM_Cadera', 'ROM_Cadera_%s', 'hip',  'ROM'};
defs(end+1,:) = {'ROM_Rodilla','ROM_Rodilla_%s','knee', 'ROM'};

% modo de cadera realmente usado en los archivos
modosArch = cellfun(@(q) q.modoCaderaUsado,SIG,'UniformOutput',false);
nFallback = nnz(~strcmp(modosArch,'inclinacionmuslo'));

filasG = [];
for k = 1:size(defs,1)
    for tk = 1:2
        if tk == 1, ejO = 'S'; ejS = 'S'; tarea = "S"; else, ejO = exOp; ejS = exSan; tarea = "Step"; end
        selO = T.Ejercicio == string(ejO); selS = T.Ejercicio == string(ejS);
        vo = T.(sprintf(defs{k,2},ladoOperado))(selO);
        vs = T.(sprintf(defs{k,2},ladoSan))(selS);
        mo = mean(vo,'omitnan'); ms = mean(vs,'omitnan');

        cal = 2; motivo = strings(0,1); sinSenal = false;
        if strcmp(defs{k,4},'EMG')
            for L = [ladoOperado ladoSan]
                m = [defs{k,3} '_' L];
                if mvcOrigen.(m) == "PICO TAREA (MVC inválido)"
                    cal = 0; motivo(end+1) = "MVC inválido " + string(L); %#ok<SAGROW>
                else
                    if mvcInfo.(m).nValidos == 1
                        cal = min(cal,1); motivo(end+1) = "MVC de un ensayo " + string(L); %#ok<SAGROW>
                    end
                    if isfinite(mvcInfo.(m).ratio) && mvcInfo.(m).ratio > 3
                        cal = min(cal,1); motivo(end+1) = "MVC inconsistente " + string(L); %#ok<SAGROW>
                    end
                end
            end
            pkO = T.(['Pico_' defs{k,3} '_' ladoOperado '_pctMVC'])(selO);
            pkS = T.(['Pico_' defs{k,3} '_' ladoSan '_pctMVC'])(selS);
            % canal sin senal en UN lado (se evalua cada lado por separado)
            for iL = 1:2
                if iL == 1, pkL = pkO; Ls = ladoOperado; else, pkL = pkS; Ls = ladoSan; end
                if isempty(pkL) || all(~isfinite(pkL)) || max(pkL,[],'omitnan') < umbralCanalPlano_pct
                    cal = 0; sinSenal = true;
                    motivo(end+1) = sprintf("canal sin señal %s (pico < %g %%MVC)",Ls,umbralCanalPlano_pct); %#ok<SAGROW>
                end
            end
            % [v3.2] solo repeticiones CON DATO: antes las NaN del lado sin senal (NaN > 100 = false)
            % entraban en el denominador y diluian el porcentaje
            pk = [pkO; pkS];
            pk = pk(isfinite(pk));
            if ~isempty(pk)
                fr100 = mean(pk > 100);
                if fr100 >= fracRepsSobre100
                    cal = min(cal,1); motivo(end+1) = sprintf("%.0f %% de repeticiones con pico > 100 %% MVC",100*fr100); %#ok<SAGROW>
                end
                if max(pk) < 15
                    cal = min(cal,1); motivo(end+1) = "activación < 15 %: MVC posiblemente inflado"; %#ok<SAGROW>
                end
            end
        else
            if strcmp(defs{k,3},'hip') && ~caderaPorEje
                % Cadera sin pelvis (inclinacion del muslo o muslo por repeticion): no hay eje SVD
                % pelvis-muslo que evaluar. Tope 1: no descuenta la inclinacion de la pelvis.
                cal = min(cal,1);
                if strcmpi(modoCadera,'inclinacionMuslo')
                    motivo(end+1) = "cadera = inclinación del muslo (no descuenta la pelvis)"; %#ok<SAGROW>
                    if nFallback > 0
                        motivo(end+1) = sprintf("%d archivo(s) con muslo relativo al inicio de cada repetición",nFallback); %#ok<SAGROW>
                    end
                else
                    motivo(end+1) = "cadera = muslo relativo al inicio de cada repetición (sin pelvis)"; %#ok<SAGROW>
                end
            else
                for L = [ladoOperado ladoSan]
                    ve = varExpl.([defs{k,3} L]);
                    if ve < umbralNoInterpEje
                        cal = 0; motivo(end+1) = sprintf("eje %s %.0f %%",L,100*ve); %#ok<SAGROW>
                    elseif ve < umbralEje
                        cal = min(cal,1); motivo(end+1) = sprintf("eje %s %.0f %%",L,100*ve); %#ok<SAGROW>
                    end
                    sel = tablaEjes.Articulacion == string([defs{k,3} L]) & tablaEjes.Archivo ~= "GLOBAL";
                    kex = keys(excluirROM);   % archivos cuyo ROM de esta articulacion se descarta
                    for ke = 1:numel(kex)
                        if any(strcmp(excluirROM(kex{ke}),[defs{k,3} L])), sel = sel & tablaEjes.Archivo ~= string(kex{ke}); end
                    end
                    vmin = min(tablaEjes.VarExplicada(sel),[],'omitnan');
                    if isfinite(vmin) && vmin < umbralNoInterpEje
                        if ejeArchivoAnulaCalidad, cal = 0; else, cal = min(cal,1); end
                        motivo(end+1) = sprintf("mín. por archivo %s %.0f %%",L,100*vmin); %#ok<SAGROW>
                    end
                    % signo ambiguo en algun archivo
                    amb = any(tablaEjes.Articulacion == string([defs{k,3} L]) & tablaEjes.SignoAmbiguo);
                    if amb, cal = min(cal,1); motivo(end+1) = "signo ambiguo " + string(L); end %#ok<SAGROW>
                end
            end
            % n efectivo: pocas repeticiones validas => LSI no interpretable
            nOp = nnz(isfinite(vo)); nSa = nnz(isfinite(vs));
            if min(nOp,nSa) < nMinROM
                cal = 0; motivo(end+1) = sprintf("n efectivo %d (op) / %d (sana)",nOp,nSa); %#ok<SAGROW>
            end
        end
        clave = sprintf('%s|%s',defs{k,1},tarea);
        if isKey(calidadManual,clave), cal = calidadManual(clave); motivo(end+1) = "ajuste manual"; end %#ok<SAGROW>
        if isempty(motivo), motivo = "OK"; end
        if ~(isfinite(mo) && isfinite(ms)), cal = NaN; end
        lsi = 100*mo/ms;
        if sinSenal, lsi = NaN; end

        g = struct('Paciente',string(paciente),'LadoOperado',string(ladoOperado), ...
            'Variable',string(defs{k,1}),'Tarea',tarea, ...
            'Op_media',mo,'Op_SD',std(vo,'omitnan'),'Op_n',nnz(isfinite(vo)), ...
            'San_media',ms,'San_SD',std(vs,'omitnan'),'San_n',nnz(isfinite(vs)), ...
            'Delta',mo-ms,'LSI',lsi,'Calidad',cal,'Motivo',strjoin(motivo,"; "));
        filasG = [filasG; g]; %#ok<AGROW>
    end
end
tablaG = struct2table(filasG);
writetable(tablaG,[paciente '_resumen_global.csv']);
disp(tablaG(:,{'Variable','Tarea','Op_media','San_media','LSI','Calidad','Motivo'}));

fprintf('\nTerminado. Figuras en la carpeta "%s".\n',carpetaFiguras);
fprintf('Revisa %s_unidades_EMG_originales.csv, %s_calidad_cadera.csv y el control de calidad EMG.\n',paciente,paciente);

%% ============================================================
% FUNCIONES LOCALES
% =============================================================
function w = ventanaT(t,rest)
    if any(rest), w = [t(find(rest,1,'first')) t(find(rest,1,'last'))]; else, w = [NaN NaN]; end
end

function f = nuevaFigura(nombre,pos)
    f = figure('Name',nombre,'Color','w','Position',pos,'Visible','off');
    try, theme(f,'light'); catch, end %#ok<NOCOM>
end

function guardarYMostrar(f,archivo,mostrar)
    drawnow;
    try, exportgraphics(f,archivo,'Resolution',150,'BackgroundColor','white');
    catch, saveas(f,archivo); end
    if mostrar, f.Visible = 'on'; else, close(f); end
end

function decorarMovimiento(q)
    grid on; yline(0,':k');
    xline([q.t(q.iStart) q.t(q.iEnd)],'--k');
    if ~isempty(q.reps)
        b = unique(q.reps(:));
        xline(q.t(b),'Color',[0.6 0.6 0.6],'LineStyle',':');
    end
end

function n = nombreDe(mapa,clave)
    if isKey(mapa,clave), n = mapa(clave); else, n = clave; end
end

function [x,unidad] = armonizarUnidadEMG(x)
    % OT BioLab exporta cada canal de cada archivo en uV o en mV. Se distingue por la
    % resolucion del ADC: 0,298 -> uV ; 0,000298 -> mV. Devuelve la senal siempre en uV.
    unidad = "uV";
    u = unique(x(isfinite(x) & x ~= 0));
    if numel(u) < 20, unidad = "sin datos"; return; end
    d = diff(u); d = d(d > 1e-9);
    if isempty(d), unidad = "sin datos"; return; end
    if min(d) < 0.01
        x = x*1000; unidad = "mV (x1000)";
    end
end

function q = limpiarQ(q,Fs,maxHueco_s)
    % Validez por norma RELATIVA (los nodos exportan con norma 8,19 o 8192).
    q = double(q);
    nm = sqrt(sum(q.^2,2));
    ref = median(nm(isfinite(nm) & nm > 0));
    if isempty(ref) || ~isfinite(ref), q(:) = NaN; return; end
    bad = any(~isfinite(q),2) | nm < 0.5*ref;
    q(bad,:) = NaN;
    last = find(~bad,1);
    if isempty(last), return; end
    for k = last+1:size(q,1)
        if bad(k), continue; end
        if dot(q(k,:),q(last,:)) < 0, q(k,:) = -q(k,:); end
        last = k;
    end
    q = fillmissing(q,'linear','MaxGap',round(maxHueco_s*Fs),'EndValues','none');
    n = sqrt(sum(q.^2,2)); q = q./n;
end

function rest = detectarReposo(Qs,Fs,win_s,search_s)
    N = size(Qs{1},1); sp = zeros(N,1); valid = true(N,1);
    for k = 1:numel(Qs)
        q = Qs{k}; valid = valid & all(isfinite(q),2);
        d = min(abs(sum(q(1:end-1,:).*q(2:end,:),2)),1);
        sp(2:end) = sp(2:end) + 2*acosd(d)*Fs;
    end
    sp(~valid | ~isfinite(sp)) = 1e6;
    w = max(10,round(win_s*Fs));
    m = movmean(sp,w); vf = movmean(double(valid),w);
    lo = ceil(w/2)+1; hi = min(N-ceil(w/2)-1,round(search_s*Fs));
    cand = lo:hi; cand = cand(vf(cand) > 0.99);
    rest = false(N,1);
    if isempty(cand)
        warning('No se encontró ventana de reposo válida; se usan las primeras muestras válidas.');
        iv = find(valid,w); rest(iv) = true; return;
    end
    [~,k] = min(m(cand)); i0 = cand(k);
    rest(max(1,i0-floor(w/2)):min(N,i0+floor(w/2))) = true;
end

function r = corrDI(a,b)
    a = a(:); b = b(:);
    ok = isfinite(a) & isfinite(b);
    if nnz(ok) < 100 || std(a(ok)) == 0 || std(b(ok)) == 0, r = NaN; return; end
    c = corrcoef(a(ok),b(ok)); r = c(1,2);
end

function lag = lagIzqVsDer(kD,kI,Fs,maxLag_s)
    % Lag (s) de la rodilla I respecto a la D por CORRELACION CRUZADA. >0: izquierda retrasada.
    % (El estimador por picos fallaba con curvas de meseta, como sentarse-levantarse.)
    a = fillmissing(kD(:),'constant',0); b = fillmissing(kI(:),'constant',0);
    idx = find(abs(a) > 0.3*max(abs(a)) | abs(b) > 0.3*max(abs(b)));
    if numel(idx) < round(2*Fs), lag = 0; return; end
    i1 = idx(1); i2 = idx(end);
    a = a(i1:i2); b = b(i1:i2);
    a = a - mean(a); b = b - mean(b);
    [c,l] = xcorr(b,a,round(maxLag_s*Fs),'coeff');
    [cm,i] = max(c);
    lag = l(i)/Fs;
    if cm < 0.5, lag = 0; end
end

function [rv,Rout] = rotvecRel(qa,qb,rest)
    valid = all(isfinite([qa qb]),2);
    qa(~valid,:) = repmat([1 0 0 0],nnz(~valid),1);
    qb(~valid,:) = repmat([1 0 0 0],nnz(~valid),1);
    A = quaternion(qa(:,1),qa(:,2),qa(:,3),qa(:,4));
    B = quaternion(qb(:,1),qb(:,2),qb(:,3),qb(:,4));
    R = conj(A).*B;
    r0 = rest & valid;
    if nnz(r0) < 10, r0 = false(size(valid)); r0(find(valid,200)) = true; end
    Rc = conj(meanrot(R(r0))).*R;
    [w,qx,qy,qz] = parts(Rc);
    wN = w; xN = qx; yN = qy; zN = qz;
    wN(~valid) = NaN; xN(~valid) = NaN; yN(~valid) = NaN; zN(~valid) = NaN;
    Rout = quaternion(wN,xN,yN,zN);
    sg = ones(size(w)); sg(w < 0) = -1;
    Rc = quaternion(sg.*w,sg.*qx,sg.*qy,sg.*qz);
    rv = rotvecd(Rc);
    rv(~valid,:) = NaN;
end

function [inc,info] = inclinacionMuslos(qD,restD,qI,restI,mov,cfg)
    % Angulo SAGITAL del eje largo de cada muslo respecto a la VERTICAL, en grados.
    %   0 = postura de reposo (de pie); + = flexion (hacia donde se inclina el muslo al flexionar).
    % No usa la pelvis y no depende del rumbo del paciente (un giro sobre la vertical no cambia
    % la inclinacion). Condicion: el marco de referencia del IMU debe tener el eje z vertical.
    % Se comprueba en reposo: el eje del sensor mas vertical del muslo debe tener |z| >= cfg.minVert.
    N = size(qD,1);
    inc  = struct('D',NaN(N,1),'I',NaN(N,1));
    info = struct('ok',false,'msg','','conv','','eje',NaN,'vert',NaN,'consist',NaN,'tiltMax',[NaN NaN]);
    Q = {qD,qI}; RST = {restD,restI};
    Rm = cell(1,2); R0 = cell(1,2);
    for s = 1:2
        q = Q{s};
        v = all(isfinite(q),2);
        r0 = RST{s} & v;
        if nnz(r0) < 10, info.msg = 'reposo sin datos válidos'; return; end
        qq = q; qq(~v,:) = repmat([1 0 0 0],nnz(~v),1);
        Qo = quaternion(qq(:,1),qq(:,2),qq(:,3),qq(:,4));
        Qref = meanrot(Qo(r0));
        Rr = rotmat(Qo,'point');            % 3x3xN: eje k del sensor en el marco mundo = Rr(:,k,:)
        Rr(:,:,~v) = NaN;
        Rm{s} = Rr;
        R0{s} = rotmat(Qref,'point');
    end

    % eje largo = eje del sensor mas vertical en reposo (convencion A: sensor->mundo; B: inversa)
    cA = zeros(1,3); cB = zeros(1,3);
    for k = 1:3
        cA(k) = (abs(R0{1}(3,k)) + abs(R0{2}(3,k)))/2;
        cB(k) = (abs(R0{1}(k,3)) + abs(R0{2}(k,3)))/2;
    end
    [mA,kA] = max(cA); [mB,kB] = max(cB);
    if mA >= mB, conv = 'A'; k = kA; vert = mA; else, conv = 'B'; k = kB; vert = mB; end
    info.conv = conv; info.eje = k; info.vert = vert;
    if vert < cfg.minVert
        info.msg = sprintf(['en reposo el eje más vertical del muslo solo tiene |z| = %.2f (< %.2f): ' ...
                            'el marco del IMU no parece alineado con la gravedad'],vert,cfg.minVert);
        return;
    end

    Z = cell(1,2); H = cell(1,2); tilt = cell(1,2);
    for s = 1:2
        if conv == 'A'
            zr = squeeze(Rm{s}(3,k,:)); hx = squeeze(Rm{s}(1,k,:)); hy = squeeze(Rm{s}(2,k,:));
            sg = sign(R0{s}(3,k));
        else
            zr = squeeze(Rm{s}(k,3,:)); hx = squeeze(Rm{s}(k,1,:)); hy = squeeze(Rm{s}(k,2,:));
            sg = sign(R0{s}(k,3));
        end
        if sg == 0, sg = 1; end
        Z{s}    = max(-1,min(1,sg*zr(:)));      % componente vertical del eje (1 = vertical)
        H{s}    = sg*[hx(:) hy(:)];             % componente horizontal
        tilt{s} = acosd(Z{s});
    end

    % sentido "adelante": direccion horizontal media del muslo cuando esta claramente inclinado
    U = zeros(0,2);
    for s = 1:2
        m = sqrt(sum(H{s}.^2,2));
        ok = isfinite(tilt{s}) & tilt{s} > cfg.tiltMinF & m > 0.3 & mov(:);
        U = [U; H{s}(ok,:)./m(ok)]; %#ok<AGROW>
    end
    if size(U,1) < 100
        info.msg = 'muy poca flexión del muslo para fijar el sentido "adelante"'; return;
    end
    fm = mean(U,1); cons = norm(fm); info.consist = cons;
    if cons < cfg.minConsist
        info.msg = sprintf('dirección de flexión inconsistente (%.2f < %.2f)',cons,cfg.minConsist); return;
    end
    f = fm/cons;

    nombres = {'D','I'};
    for s = 1:2
        th = atan2d(H{s}*f(:),Z{s});
        th(~isfinite(tilt{s})) = NaN;
        off = median(th(RST{s} & isfinite(th)),'omitnan');
        if ~isfinite(off), off = 0; end
        inc.(nombres{s}) = th - off;
        info.tiltMax(s) = max(tilt{s});
    end
    info.ok = true;
end

function [a,aRaw,info] = anguloContinuo(rv,ax,Fs,rr,cfg)
    a = rv*ax';
    nS = max(1,round(0.05*Fs));
    aRaw = movmean(a,nS,'omitnan');
    N = numel(a);
    info = struct('glitches',0,'pctSalto',0,'pctRango',0,'pctBase',0,'pctValido',0);
    g = [false; abs(diff(a)) > cfg.maxSalto];
    nm = max(1,round(cfg.margen*Fs));
    gd = conv(double(g),ones(2*nm+1,1),'same') > 0;
    info.glitches = nnz(diff([0; double(g)]) == 1);
    info.pctSalto = 100*nnz(gd & isfinite(a))/N;
    a(gd) = NaN;
    m = movmean(a,nS,'omitnan'); m(isnan(a)) = NaN; a = m;
    off = median(a(rr),'omitnan'); if ~isfinite(off), off = 0; end
    a = a - off; aRaw = aRaw - off;
    r1 = abs(a) > cfg.maxAng;
    info.pctRango = 100*nnz(r1)/N; a(r1) = NaN;
    base = movmin(a,max(3,round(cfg.ventBase*Fs)),'omitnan');
    r2 = isfinite(a) & abs(base) > cfg.maxBase;
    info.pctBase = 100*nnz(r2)/N; a(r2) = NaN;
    info.pctValido = 100*mean(isfinite(a));
end

function [a,ok,expl] = anguloRepRelativo(Q,ia,ib,Fs,minExpl,maxAng,cierreMax)
    % Angulo de UNA repeticion respecto a su propio inicio y con su propio eje de giro.
    % Q puede ser una rotacion relativa (pelvis->muslo) o la orientacion absoluta de un muslo.
    n = ib-ia+1; a = NaN(max(n,0),1); ok = false; expl = NaN;
    if ia < 1 || ib > numel(Q) || n < 20, return; end
    q = Q(ia:ib);
    [w,x,y,z] = parts(q);
    v = isfinite(w) & isfinite(x) & isfinite(y) & isfinite(z);
    if mean(v) < 0.95, return; end
    k0 = find(v,max(5,round(0.1*Fs)));
    if numel(k0) < 5, return; end
    Rref = meanrot(q(k0));
    d = q .* conj(Rref);
    [w,x,y,z] = parts(d);
    w(~v) = 1; x(~v) = 0; y(~v) = 0; z(~v) = 0;
    sg = ones(size(w)); sg(w < 0) = -1;
    d = quaternion(sg.*w,sg.*x,sg.*y,sg.*z);
    rv = rotvecd(d);
    rv(~v,:) = NaN;
    [~,S,V] = svd(rv(v,:),'econ');
    ax = V(:,1)'; expl = S(1,1)^2/sum(diag(S).^2);
    p = rv*ax';
    if max(p) < -min(p), p = -p; end
    a = p;
    last = find(isfinite(a),1,'last');
    ok = expl >= minExpl && max(abs(a)) <= maxAng && abs(a(last)) <= cierreMax;
end

function ok = repCaderaValida(y,cierreMax,maxAng)
    y = y(:); n = numel(y); k = max(3,round(0.05*n));
    ini = median(y(1:k),'omitnan'); fin = median(y(end-k+1:end),'omitnan');
    ok = mean(isfinite(y)) >= 0.95 && isfinite(ini) && isfinite(fin) && ...
         abs(fin-ini) <= cierreMax && max(abs(y)) <= maxAng;
end

function graficoBarrasEMG(T,ejs,nomEj,musculos,nomMus,prefijo,etiquetaY,titulo)
    nM = numel(musculos); nE = numel(ejs); M = nan(nM,nE); S = nan(nM,nE);
    for ie = 1:nE
        sel = T.Ejercicio == string(ejs{ie});
        for im = 1:nM
            v = T.([prefijo musculos{im} '_pctMVC'])(sel);
            M(im,ie) = mean(v,'omitnan'); S(im,ie) = std(v,'omitnan');
        end
    end
    b = bar(M,'grouped'); hold on;
    for ie = 1:nE, errorbar(b(ie).XEndPoints,M(:,ie),S(:,ie),'k','LineStyle','none','CapSize',4); end
    yline(100,'--r','100 % MVC');
    set(gca,'XTick',1:nM,'XTickLabel',nomMus,'XTickLabelRotation',25);
    ylabel(etiquetaY); grid on; title(titulo); legend(b,nomEj,'Location','best');
end

function graficoBarrasLado(T,ejs,nomEj,varD,varI,etiquetaY,titulo)
    nE = numel(ejs); M = nan(nE,2); S = nan(nE,2);
    for ie = 1:nE
        sel = T.Ejercicio == string(ejs{ie});
        M(ie,:) = [mean(T.(varD)(sel),'omitnan') mean(T.(varI)(sel),'omitnan')];
        S(ie,:) = [std(T.(varD)(sel),'omitnan')  std(T.(varI)(sel),'omitnan')];
    end
    if nE == 1, M = [M; nan(1,2)]; S = [S; nan(1,2)]; end
    b = bar(M,'grouped'); hold on;
    for k = 1:2, errorbar(b(k).XEndPoints,M(:,k),S(:,k),'k','LineStyle','none','CapSize',4); end
    xlim([0.5 nE+0.5]);
    set(gca,'XTick',1:nE,'XTickLabel',nomEj);
    ylabel(etiquetaY); grid on; title(titulo); legend(b,{'Derecha','Izquierda'},'Location','best');
end

function reps = segmentarRepeticiones(x,iStart,iEnd,Fs,distMin_s,promMin,fracProm,incluirIncompleta,centrado,tolCentrado)
    % centrado = false: repeticion = valle -> valle (cinematica).
    % centrado = true : repeticion centrada en cada pico; limites = punto medio entre picos consecutivos
    %                   (+-P/2 en los extremos). Pensado para la envolvente del EMG.
    if nargin < 9, centrado = false; end
    if nargin < 10, tolCentrado = 0.25; end
    reps = zeros(0,2);
    idx = iStart:iEnd; y = x(idx); y = y(:);
    y = fillmissing(y,'linear','EndValues','nearest');
    if numel(y) < 2*round(distMin_s*Fs) || any(~isfinite(y)), return; end
    [~,lp,~,pr] = findpeaks(y,'MinPeakDistance',round(distMin_s*Fs),'MinPeakProminence',promMin);
    if isempty(lp), return; end
    lp = lp(pr >= fracProm*max(pr));
    if isempty(lp), return; end
    nP = numel(lp);
    if nP >= 2, P = round(median(diff(lp))); else, P = round(2.5*Fs); end

    if centrado
        lim = zeros(nP+1,1);
        lim(1)    = lp(1) - round(P/2);
        lim(2:nP) = round((lp(1:end-1) + lp(2:end))/2);
        lim(nP+1) = lp(nP) + round(P/2);
        tol = round(tolCentrado*P);
        for k = 1:nP
            fuera = (lim(k) < 1 - tol) || (lim(k+1) > numel(y) + tol);
            if fuera && ~incluirIncompleta, continue; end
            a = max(1,lim(k)); b = min(numel(y),lim(k+1));
            reps(end+1,:) = (idx(1)-1) + [a b]; %#ok<AGROW>
        end
        return;
    end

    valle = zeros(nP+1,1);
    % primer valle: ultimo punto cercano a la linea base ANTES de la subida (si no, la primera
    % repeticion arrastra el reposo inicial y sale mucho mas larga que las demas)
    a = max(1,lp(1)-P); segI = y(a:lp(1)); mnI = min(segI);
    kI = find(segI <= mnI + 0.15*(y(lp(1))-mnI),1,'last');
    if isempty(kI), [~,kI] = min(segI); end
    valle(1) = a+kI-1;
    for k = 1:nP-1, [~,m] = min(y(lp(k):lp(k+1))); valle(k+1) = lp(k)+m-1; end
    b = min(numel(y),lp(nP)+P); [~,m] = min(y(lp(nP):b)); valle(nP+1) = lp(nP)+m-1;
    incompleta = valle(nP+1) >= b-2;
    nRep = nP; if incompleta && ~incluirIncompleta, nRep = nP-1; end
    for k = 1:nRep, reps(end+1,:) = (idx(1)-1) + [valle(k) valle(k+1)]; end %#ok<AGROW>
end

function plotBanda(x,M,c,nombre,indiv)
    if nargin >= 5 && indiv
        plot(x,M','Color',0.55*c+0.45,'LineWidth',0.5,'HandleVisibility','off');
    end
    mu = mean(M,1,'omitnan'); sd = std(M,0,1,'omitnan');
    if size(M,1) < 2, sd = zeros(size(mu)); end
    ok = isfinite(mu) & isfinite(sd);
    if any(ok)
        fill([x(ok) fliplr(x(ok))],[mu(ok)+sd(ok) fliplr(mu(ok)-sd(ok))],c,'FaceAlpha',0.15, ...
            'EdgeColor','none','HandleVisibility','off');
    end
    plot(x,mu,'Color',c,'LineWidth',1.8,'DisplayName',nombre);
end

function datos = cargarCSV(archivo)
    combos = {{';',','},{';','.'},{',','.'},{'\t','.'},{'\t',','}};
    datos = []; d = [];
    for k = 1:numel(combos)
        try
            d = readmatrix(archivo,'Delimiter',combos{k}{1},'DecimalSeparator',combos{k}{2});
        catch
            continue;
        end
        d = d(:,sum(isfinite(d),1) > 0);
        d = d(~isnan(d(:,1)),:);
        if size(d,2) >= 49
            datos = d;
            if k > 1
                fprintf('  %s leído con delimitador "%s" y decimal "%s"\n',archivo,combos{k}{1},combos{k}{2});
            end
            return;
        end
    end
    fprintf('  %s: ninguna combinación dio 49 columnas (mejor intento: %d).\n',archivo,size(d,2));
end

function [y,unidad] = procesarEMG(x,Fs,fLow,fHigh,ventanaRMS_s)
    x = double(x(:));
    [x,unidad] = armonizarUnidadEMG(x);
    x = fillmissing(x,'linear','EndValues','nearest');
    [b,a] = butter(4,[fLow fHigh]/(Fs/2),'bandpass'); x = filtfilt(b,a,x);
    N = max(1,round(ventanaRMS_s*Fs));
    y = sqrt(movmean(x.^2,N,'omitnan'));
end

function [val,info] = calcularMVC(archivos,columna,Fs,fLow,fHigh,ventanaRMS_s,fracMin,nombreM)
    vals = NaN(numel(archivos),1);
    for k = 1:numel(archivos)
        f = archivos{k};
        if ~isfile(f), error('Falta el archivo MVC %s.',f); end
        d = cargarCSV(f);
        if size(d,2) < columna, error('%s no contiene la columna %d.',f,columna); end
        [y,uni] = procesarEMG(d(:,columna),Fs,fLow,fHigh,ventanaRMS_s);
        m = round(0.5*Fs); if numel(y) > 2*m, y = y(m+1:end-m); end
        vals(k) = max(y,[],'omitnan');
        fprintf('%s | %s | columna %d | unidad original %s | MVC RMS=%.5g uV\n',f,nombreM,columna,uni,vals(k));
    end
    ok = vals >= fracMin*max(vals);
    if any(~ok)
        warning('%s: descartados %d ensayo(s) con escala incompatible (%s).',nombreM,nnz(~ok), ...
            strjoin(archivos(~ok),', '));
    end
    val = max(vals(ok),[],'omitnan');
    info.nEnsayos = numel(archivos); info.nValidos = nnz(ok); info.nDescartados = nnz(~ok);
    info.ratio = NaN;
    if nnz(ok) > 1, info.ratio = max(vals(ok))/min(vals(ok)); end
    if isfinite(info.ratio) && info.ratio > 3
        warning('%s: ensayos de MVC poco consistentes (max/min = %.1f).',nombreM,info.ratio);
    end
    if ~isfinite(val) || val <= 0, val = NaN; end
end

function x = rellenarHuecos(x,maxGap)
    x = logical(x(:)); if maxGap <= 0 || ~any(x), return; end
    z = diff([false;x;false]); a = find(z==1); b = find(z==-1)-1;
    for k = 1:numel(a)-1
        gap = a(k+1)-b(k)-1;
        if gap > 0 && gap <= maxGap, x(b(k)+1:a(k+1)-1) = true; end
    end
end

function x = quitarTramosCortos(x,minLen)
    x = logical(x(:)); if ~any(x), return; end
    z = diff([false;x;false]); a = find(z==1); b = find(z==-1)-1;
    for k = 1:numel(a), if b(k)-a(k)+1 < minLen, x(a(k):b(k)) = false; end, end
end

function r = rangoSeguro(x)
    x = x(isfinite(x)); if isempty(x), r = NaN; else, r = max(x)-min(x); end
end
