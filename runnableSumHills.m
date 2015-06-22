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

BeginPackage["sumHillsFofT`"]
(* Exported symbols added here with SymbolName::usage *)

sumHills::usage = "sumHills[HILLS_file, options] returns a list of 2D arrays that
  are the time steps of the growth of the height of the negative of the free energy
  surface from a PLUMED metadynamics calculation.
  Only made for 2 collective variables currently, but that can't be changed by
  making it check for the length of a row in the input data."
(* todo if we ever do well tempered metadynamics, might need to include bias factor? *)

plotHills::usage = "plotHills[list of matrices, options] Takes output of sumHills
  and plots time steps."

plotHillsPoint::usage = "plotHillsPoint[list of matrices, {x, y}, options] takes output of
  sumHills and plots the selected point as a function of time."

(* Begin Private Context *)
Begin["`Private`"]

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
      gridCV1 = Table[i, Evaluate[{i, ## & @@ minMaxCV1, gridSize}]];
      gridCV2 = Table[i, Evaluate[{i, ## & @@ minMaxCV2, gridSize}]];
      Print["Found grid parameters:"];
      Print["  Collective variable 1 range: ", minMaxCV1];
      Print["  Collective variable 2 range: ", minMaxCV2];
      Print["  Grid dimensions: ", gridLengthCV1, ", ", gridLengthCV2];
      Print["  Size of time chunks: ", timeChunkwUnits];
      (* Create gaussian matrix that will be translated as needed later. *)
      gaussianMatrix = GaussianMatrix[
        {{gridLengthCV1, gridLengthCV2},
          {sigmaCV1 / gridSize, sigmaCV2 / gridSize}},
        Method -> "Gaussian"]
          * 2 Pi (sigmaCV1 * sigmaCV2) / gridSize^2;
      (* Function that will first find the offset of the current point
    to the center of gaussian matrix scaled to the grid.
    Then, it will rotate the center to that point using RotateLeft.
    Finally, it will crop the matrix to the size of the grid.*)
      scaledRotatedGaussMat[row_] := Return[
        RotateLeft[
          gaussianMatrix * row[[6]],
          Round[
            {gridLengthCV1 - (row[[2]] - minMaxCV1[[1]])/gridSize,
              gridLengthCV2 - (row[[3]] - minMaxCV2[[1]])/gridSize}
          ]][[1 ;; gridLengthCV1, 1 ;; gridLengthCV2]]
      ];
      grid2D = Array[
        {gridCV1[[#1]], gridCV2[[#2]]} &,
        {gridLengthCV1, gridLengthCV2}];
      Print["Processing data..."];
      (* Apply the function, in parallel to save some time hopefully. *)
      processedData =
          Function[timePoint,
          (* Join height with coordinates, then flatten the array. *)
            Flatten[Join[grid2D,
              Partition[#, 1] & /@ timePoint, 3], 1]] /@
              Accumulate[
                ParallelMap[
                  Chop[Total[
                    (
                      If[
                        Mod[Round[#[[1]], 0.1], 10 * timeChunkwUnits] == 0,
                        Print["Time step: ", #[[1]]],
                        ""];
                      scaledRotatedGaussMat[#]
                    ) & /@ #]] &,
                (* Partition into chunks of size timeChunk,
                   non-overlapping, no overhang, no padding *)
                  Partition[rawdata, timeChunk, timeChunk, {1, 1}, {}]]];
      Print["Done processing data. Setting values for output..."];
      (* Sum the consecutive Gaussians. This may be the slowest step,
    but I don't know how it can be done in parallel.
    It could be chunked into time steps which are then summed
    in parallel, but the accumulation still seems like it would
    need to be done in serial.*)
      (*accumulatedGaussians = Accumulate[timedGaussians];*)
      (*Print[Dimensions[accumulatedGaussians]];*)
      (* Add coordinates to the accumulated data *)
      (*withCoords = Map[*)
      (*Function[timePoint,*)
      (*Flatten[ParallelArray[*)
      (*{gridCV1[[#1]], gridCV2[[#2]], timePoint[[#1, #2]]} &,*)
      (*{gridLengthCV1, gridLengthCV2},*)
      (*DistributedContexts -> Automatic],*)
      (*1]],*)
      (*accumulatedGaussians];*)
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
      Print["Output values set. Exiting sumHills"];
      variableName
    ]

Options[plotHills] =
    {
      manipulate -> True,
      timePoint -> Automatic,
      PlotRange -> All,
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
          {{i, timeLength, "Time Chunk"}, 1, timeLength, 1,
            Appearance->"Labeled"}
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
              FrameLabel -> {"Time / ps", "- (Free Energy)"},
              FilterRules[{tempopts}, Options[ListLinePlot]]]],
            Show[
              ListDensityPlot[lastTimePoint,
                FilterRules[{tempopts}, Options[ListDensityPlot]]],
              Graphics[Locator[Dynamic[spotxy]]
              ]]}],
          UnsavedVariables -> {spotxy}
        ],
        Print["Taking data at point ", locationxy];
        (* From All times, take determined location, then just take the height there. *)
        plotData = Transpose[{times, Flatten[data[[All, location, 3]]]}];
        plot = ListLinePlot[plotData,
          FrameLabel -> {"Time", "- (Free Energy)"},
          FilterRules[{tempopts}, Options[ListLinePlot]]];
        Return[plot]
      ]
    (* If I add anything here, need to change above because this is set up to return
    the value of the the "If" statement, so adding a semicolon will cause a dynamic
    plot not to be returned. *)
    ]

(* End Private Context *)
End[]

EndPackage[]

LaunchKernels[1]

Needs["sumHillsFofT`"]

Print["Loaded sum hills package, applying..."]

output = sumHills[inFileName, name -> Evaluate[varName]]

Print["sumHills complete, trying to save file..."]

FullDefinition[output] >> "mathematicaHILLS.m"

Print["File saved; done; quitting..."]

Quit[]