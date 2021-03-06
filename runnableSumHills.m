#!/usr/local/bin/MathematicaScript -script

(* This function needs to be executable. It can be called with 0, 1, or 2 arguments.
If provided, the first argument is the name of the HILLS file which is HILLS by default.
If provided, the second argument is the name of the variable of the output data.
Again, HILLS by default.
It will save everything as mathematicaHILLS.m in the current directory. *)

If[Length[$ScriptCommandLine] > 1,
  If[Length[$ScriptCommandLine] > 2,
    If[Length[$ScriptCommandLine] > 3,
      Print["Ignoring unknown positional arguments ",
        $ScriptCommandLine[[4;;]]],
      ""
    ];
    varName = ToExpression[$ScriptCommandLine[[3]]],
    varName = Automatic
  ];
  inFileName = $ScriptCommandLine[[2]],
  inFileName = "HILLS";
  varName = Automatic
];

(* ::Package:: *)

SetOptions[$Output, FormatType -> OutputForm];

LaunchKernels[1]

(* Mathematica Package         *)
(* Created by IntelliJ IDEA    *)

(* :Title: sumHillsFofT     *)
(* :Context: sumHillsFofT`  *)
(* :Author: Thomas Heavey   *)
(* :Date: 7/07/15           *)

(* :Package Version: 0.2.8     *)
(* :Mathematica Version: 9     *)
(* :Copyright: (c) 2015 Thomas Heavey *)
(* :Keywords:                  *)
(* :Discussion:                *)


processData =
    Compile[{{data, _Real, 2}, {grid2D, _Real, 3}, {gaussianMatrix, _Real, 2},
      {gridLengthCV1, _Integer}, {gridLengthCV2, _Integer},
      {minMaxCV1, _Real, 1}, {minMaxCV2, _Real, 1}, {gridSize, _Real},
      {timeChunk, _Integer}, {filler, _Real, 1}},
    (* Join height with coordinates, then flatten the array. *)
      Flatten[Join[grid2D,
        Partition[#, 1] & /@ #, 3], 1] & /@
          Accumulate[
            Map[
              Total[
                RotateLeft[
                  - gaussianMatrix * #[[6]],
                  Round[
                    {gridLengthCV1 - (#[[2]] - minMaxCV1[[1]])/gridSize,
                      gridLengthCV2 - (#[[3]] - minMaxCV2[[1]])/gridSize}
                  ]][[1 ;; gridLengthCV1, 1 ;; gridLengthCV2]] & /@ #] &,
            (* Partition into chunks of size timeChunk,
                   non-overlapping, no overhang,
                   padded with a row of 0. if needed *)
              Partition[data, timeChunk, timeChunk, {1, 1}, {filler}]]],
      {{Partition[_, _, __], _Real, 3},
        {Partition[_, 1], _Real, 3}},
      CompilationTarget -> "C"
    ];

Options[sumHills] =
    {
      GridSize -> 0.1,
      TimeChunkSize -> 1000, (* 1000 is chunking to tenths of nanoseconds *)
      name -> Automatic
    };

sumHills[hillsFileName_, OptionsPattern[]]:=
    Module[
      {
        rawdata,
        sigmaCV1, sigmaCV2,
        minMaxCV1, minMaxCV2,
        gridLengthCV1, gridLengthCV2,
        gridCV1, gridCV2, grid2D,
        gridSize,
        timeChunk, timeChunkwUnits,
        gaussianMatrix,
        scaledRotatedGaussMat,
        filler,
        processedData,
        variableName
      },
    (* Assign name for output of data *)
      variableName = If[
        OptionValue[name] === Automatic,
      (* Take data file name and keep only alphanumerics. *)
        ToExpression[StringReplace[hillsFileName, Except[WordCharacter] -> ""]],
      (* Use given name. *)
        OptionValue[name]];
      Print["Data will be output as ", ToString[variableName]];
      (* Import data, checking for comments and empty elements*)
      Print["Importing data from ", hillsFileName];
      rawdata = DeleteCases[#, {_String, __} | {}]& @ Import[hillsFileName, "Table"];
      Print["Data imported successfully"];
      sigmaCV1 = rawdata[[1,4]];
      sigmaCV2 = rawdata[[1,5]];
      minMaxCV1={Min[rawdata[[All, 2]]], Max[rawdata[[All, 2]]]};
      minMaxCV2={Min[rawdata[[All, 3]]], Max[rawdata[[All, 3]]]};
      gridSize = OptionValue[GridSize];
      timeChunk = OptionValue[TimeChunkSize];
      timeChunkwUnits = Round[timeChunk * rawdata[[1, 1]]];
      DistributeDefinitions[timeChunkwUnits];
      (* Find size (dimensions) of grid needed. *)
      gridLengthCV1 = Ceiling[(minMaxCV1[[2]] - minMaxCV1[[1]]) / gridSize];
      gridLengthCV2 = Ceiling[(minMaxCV2[[2]] - minMaxCV2[[1]]) / gridSize];
      (* Values along grid axes *)
      gridCV1 = Round[Table[i, Evaluate[{i, ## & @@ minMaxCV1, gridSize}]], gridSize];
      gridCV2 = Round[Table[i, Evaluate[{i, ## & @@ minMaxCV2, gridSize}]], gridSize];
      Print["Found grid parameters:"];
      Print["  Collective variable 1 range: ", minMaxCV1];
      Print["  Collective variable 2 range: ", minMaxCV2];
      Print["  Grid dimensions: ", gridLengthCV1, ", ", gridLengthCV2];
      Print["  Size of time chunks: ", timeChunkwUnits];
      (* Create gaussian matrix that will be translated as needed later. *)
      gaussianMatrix = Chop[GaussianMatrix[
        {{gridLengthCV1, gridLengthCV2},
          {sigmaCV1 / gridSize, sigmaCV2 / gridSize}},
        Method -> "Gaussian"]
          * 2 Pi (sigmaCV1 * sigmaCV2) / gridSize^2,
        10^-100];
      (* Function that will first find the offset of the current point
    to the center of gaussian matrix scaled to the grid.
    Then, it will rotate the center to that point using RotateLeft.
    Finally, it will crop the matrix to the size of the grid.*)
      grid2D = Array[
        {gridCV1[[#1]], gridCV2[[#2]]} &,
        {gridLengthCV1, gridLengthCV2}];
      filler = {0., 0., 0., 0., 0., 0., 0.};
      Print["Processing data..."];
      processedData = processData[rawdata, grid2D, gaussianMatrix, gridLengthCV1, gridLengthCV2,
        minMaxCV1, minMaxCV2, gridSize, timeChunk, filler];
      Print["Done processing data"];
      (* Set downvalues of output *)
      Evaluate[variableName][getData] = processedData;
      Evaluate[variableName][getMinMax] = {minMaxCV1, minMaxCV2};
      Evaluate[variableName][getGridSize] = gridSize;
      Evaluate[variableName][getGrid] = {gridCV1, gridCV2};
      (* Times of time chunks (only rows beginning through end by every timeChunk) *)
      Evaluate[variableName][getTimes] = rawdata[[;; ;; timeChunk, 1]];
      (* Set upvalues of output *)
      Evaluate[variableName] /: Plot[Evaluate[variableName],
        opts:OptionsPattern[plotHills]] :=
          plotHills[Evaluate[variableName], opts];
      Evaluate[variableName] /: Plot[Evaluate[variableName]] :=
          plotHills[Evaluate[variableName]];
      Evaluate[variableName] /: Plot[Evaluate[variableName],
        {a_, b_},
        opts:OptionsPattern[plotHillsPoint]] :=
          plotHillsPoint[Evaluate[variableName], {a, b}, opts];
      Evaluate[variableName] /: Plot[Evaluate[variableName], {a_, b_}] :=
          plotHillsPoint[Evaluate[variableName], {a, b}];
      Evaluate[variableName] /: Plot[Evaluate[variableName], "diff",
        opts:OptionsPattern[plotHillsDiff]] :=
          plotHillsDiff[Evaluate[variableName], opts];
      Evaluate[variableName] /: Plot[Evaluate[variableName], "diff"] :=
          plotHillsDiff[Evaluate[variableName]];
      variableName
    ]

Options[plotHills] =
    {
      manipulate -> True,
      timePoint -> Automatic,
      PlotRange -> All,
      ColorFunction -> "TemperatureMap",
      ## & @@
          Options[ListPlot3D],
      ## & @@
          Options[Manipulate]
    };

plotHills[dataName_, opts:OptionsPattern[plotHills]]:=
    Module[
      {
        data,
        tempopts,
        timepoint,
        timeLength,
        plot
      },
      tempopts = {opts} ~Join~ Options[plotHills];
      data = dataName[getData];
      timeLength = Length[data];
      timepoint = If[
        OptionValue[timePoint] === Automatic,
        -1,
        If[
          Abs[OptionValue[timePoint]] > timeLength,
          Print["Given timepoint not in data, using last point"];
          -1,
          OptionValue[timePoint]
        ]
      ];
      If[OptionValue[manipulate],
        plot = Manipulate[
          ListPlot3D[data[[i]],
            FilterRules[{tempopts}, Options[ListPlot3D]]],
          {{i, timepoint, "Time Chunk"}, 1, timeLength, 1,
            Appearance -> "Labeled"}
        (*FilterRules[{tempopts}, Options[Manipulate]]*)
        ],
        plot = ListPlot3D[data[[timepoint]],
          FilterRules[{tempopts}, Options[ListPlot3D]]]
      ];
      plot
    ]

Options[plotHillsPoint] =
    {
      dynamic -> False,
      PlotRange -> All,
      Frame -> True,
      LabelStyle -> Black,
      ImageSize -> Medium,
      ## & @@ Options[ListLinePlot],
      ## & @@ Options[ListDensityPlot]
    };

plotHillsPoint[dataName_, {x_:Null, y_:Null}, opts:OptionsPattern[]]:=
    Module[
      {
        data, lastTimePoint, times,
        tempopts,
        minMaxCV1, minMaxCV2,
        xChecked, yChecked,
        nearestFunction, nearestFunctionxy,
        location, locationxy,
        plotData,
        plot
      },
      tempopts = {opts} ~Join~ Options[plotHillsPoint];
      data = dataName[getData];
      {minMaxCV1, minMaxCV2} = dataName[getMinMax];
      times = dataName[getTimes];
      (* Check x and y values. Use Mean if invalid *)
      xChecked = If[
        x === Null || ! IntervalMemberQ[Interval[minMaxCV1], x],
        Print["Invalid x coordinate."];
        Mean[minMaxCV1],
        x];
      yChecked = If[
        y === Null || ! IntervalMemberQ[Interval[minMaxCV2], y],
        Print["Invalid y coordinate."];
        Mean[minMaxCV2],
        y];
      (* Use Nearest to find best estimate of requested location on the grid. *)
      (* Arguments are 1: the data (just taking the first time point),
    2: -> Automatic maps the data onto the integers so that it gives the
    position of the nearest, not the value, so I don't have to search again
    afterwards. 3: the requested (input) coordinates.
    If two are equally close, not quite sure what it will do. *)
      nearestFunction = Nearest[data[[1]][[All, 1;;2]] -> Automatic];
      nearestFunctionxy = Nearest[data[[1]][[All, 1;;2]]];
      location =  nearestFunction[{xChecked, yChecked}];
      locationxy = data[[1]][[location, 1;;2]][[1]];
      If[OptionValue[dynamic],
      (*Print[Dimensions[data]];*)
      (*Print[Dimensions[data[[-1]]]];*)
        lastTimePoint = data[[-1]];
        DynamicModule[
          {
            spotxy = locationxy
          },
          Column[{
            Dynamic[spotxy],
            Dynamic[ListLinePlot[
              Transpose[{times,
                Flatten[
                  data[[All,
                      nearestFunction[spotxy][[1]],
                      3
                      ]]]}],
              FrameLabel -> {"Time / ps", "Free Energy"},
              FilterRules[{tempopts}, Options[ListLinePlot]]]],
            Show[
              ListDensityPlot[lastTimePoint,
                ColorFunction -> "TemperatureMap",
                FilterRules[{tempopts}, Options[ListDensityPlot]]],
              Graphics[Locator[Dynamic[spotxy]]
              ]]}],
          UnsavedVariables -> {spotxy}
        ],
        Print["Taking data at point ", locationxy];
        (* From All times, take determined location, then just take the height there. *)
        plotData = Transpose[{times, Flatten[data[[All, location, 3]]]}];
        plot = ListLinePlot[plotData,
          FrameLabel -> {"Time", "Free Energy"},
          FilterRules[{tempopts}, Options[ListLinePlot]]];
        Return[plot]
      ]
    (* If I add anything here, need to change above because this is set up to return
    the value of the the "If" statement, so adding a semicolon will cause a dynamic
    plot not to be returned. *)
    ]

Options[plotHillsDiff] =
    {
      ColorFunction -> "TemperatureMap",
      ## & @@ Options[ListPlot3D]
    };

plotHillsDiff[dataName_, opts:OptionsPattern[]] :=
    Module[
      {tempOpts, data, numTimePoints},
      tempOpts = {opts} ~Join~ Options[plotHillsDiff];
      data = dataName[getData];
      numTimePoints = Length[data];
      Manipulate[
        ListPlot3D[
          Transpose[{
            data[[1, All, 1]],
            data[[1, All, 2]],
            data[[i, All, 3]] - data[[i + timeDiff, All, 3]]
          }],
          FilterRules[{tempOpts}, Options[ListPlot3D]]
        ],
        {{i, 1, "Ref. Time Point"},
          1, numTimePoints - timeDiff, 1, Appearance -> "Labeled"},
        {{timeDiff, 5, "Diff. in Time"},
          1, numTimePoints - i, 1, Appearance -> "Labeled"}
      ]
    ]


Print["Loaded sum hills package, applying..."]

output = sumHills[inFileName, name -> Evaluate[varName]]

Print["sumHills complete, trying to save file..."]

FullDefinition[output] >> "mathematicaHILLS.m"

Print["File saved as mathematicaHILLS.m; done; quitting..."]

Quit[]
