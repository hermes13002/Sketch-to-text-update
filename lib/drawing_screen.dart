import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:docx_template/docx_template.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';


enum DrawingMode { rectangle, horizontalLine, verticalLine, table }

class DividerLine {
  final bool isHorizontal;
  final Offset position;
  final double length;
  Color color; // Make color mutable
  
  DividerLine({
    required this.isHorizontal,
    required this.position,
    required this.length,
    this.color = Colors.grey,
  });

  DividerLine copyWith({
    bool? isHorizontal,
    Offset? position,
    double? length,
    Color? color,
  }) {
    return DividerLine(
      isHorizontal: isHorizontal ?? this.isHorizontal,
      position: position ?? this.position,
      length: length ?? this.length,
      color: color ?? this.color,
    );
  }

  @override 
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DividerLine &&
          runtimeType == other.runtimeType &&
          isHorizontal == other.isHorizontal &&
          position == other.position &&
          length == other.length &&
          color == other.color;

  @override
  int get hashCode => 
      isHorizontal.hashCode ^ 
      position.hashCode ^ 
      length.hashCode ^ 
      color.hashCode;
}

const double _minRectangleWidth = 100.0;
const double _minRectangleHeight = 20.0;

class _DrawingState {
  final List<Rect> rectangles;
  final List<TextElement> textElements;
  final List<DividerLine> dividerLines;
  final List<TableElement> tables;

  _DrawingState({
    required this.rectangles,
    required this.textElements,
    required this.dividerLines,
    required this.tables,
  });

  _DrawingState copy() => _DrawingState(
    rectangles: List.from(rectangles),
    textElements: textElements.map((e) => TextElement(
      position: e.position,
      size: e.size,
      controller: TextEditingController(text: e.controller.text),
      fontSize: e.fontSize,
      alignment: e.alignment,
      fontFamily: e.fontFamily,
    )).toList(),
    dividerLines: List.from(dividerLines),
    tables: List.from(tables),
  );
}

class DrawingScreen extends StatefulWidget {
  const DrawingScreen({super.key});

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  final ScrollController _verticalScrollController = ScrollController();

  Offset? _startPoint;
  Offset? _currentPoint;
  List<Rect> rectangles = [];
  List<TextElement> textElements = [];
  
  bool _editMode = false;
  bool _contentEditMode = false;
  bool _positionEditMode = false;
  TextElement? _selectedElement;
  Offset? _dragStartOffset;
  bool _isResizing = false;
  Corner _resizingCorner = Corner.none;
  
  final double screenPadding = 20.0;
  List<AlignmentGuide> activeGuides = [];
  double snapThreshold = 8.0;
  bool showGrid = false;
  double gridSize = 20.0;

  DrawingMode _drawingMode = DrawingMode.rectangle;
  List<DividerLine> dividerLines = [];

  DividerLine? _selectedLine;
  bool _isLineResizing = false;
  Offset? _lineDragStartOffset;

  List<_DrawingState> _stateHistory = [];
  int _currentStateIndex = -1;

  bool _multiSelectMode = false;
  final Set<TextElement> _selectedElements = {};

  List<TableElement> tables = [];
  TableElement? _selectedTable;

  @override
  void dispose() {
    _verticalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Rectangle to Text'),
        actions: [
          if (!_multiSelectMode) ...[
            if (_editMode && _positionEditMode && _selectedLine != null)
              IconButton(
                icon: Icon(Icons.color_lens),
                onPressed: _changeSelectedLineColor,
                tooltip: 'Change line color',
              ),
              
            if (_editMode && _positionEditMode && _selectedElement != null)
              IconButton(
                icon: Icon(Icons.fit_screen),
                onPressed: _resizeSelectedToFitContent,
                tooltip: 'Resize to fit content',
              ),

            if (_editMode) ...[
              IconButton(
                icon: Icon(Icons.select_all, color: _multiSelectMode ? Colors.blue : null),
                onPressed: _toggleMultiSelectMode,
                tooltip: 'Multi-select mode',
              ),
              IconButton(
                icon: Icon(Icons.edit_note, color: _contentEditMode ? Colors.blue : null),
                onPressed: () {
                  setState(() {
                    _contentEditMode = true;
                    _positionEditMode = false;
                    _multiSelectMode = false;
                    activeGuides.clear();
                  });
                },
              ),
              IconButton(
                icon: Icon(Icons.open_with, color: _positionEditMode ? Colors.blue : null),
                onPressed: () {
                  setState(() {
                    _contentEditMode = false;
                    _positionEditMode = true;
                    _multiSelectMode = false;
                  });
                },
              ),
              IconButton(
                icon: Icon(Icons.grid_on, color: showGrid ? Colors.blue : null),
                onPressed: () {
                  setState(() {
                    showGrid = !showGrid;
                  });
                },
                tooltip: 'Toggle Grid',
              ),
              IconButton(
                icon: Icon(Icons.delete, color: Colors.red),
                onPressed: () {
                  if (_selectedElement != null) {
                    _deleteSelectedElement();
                  } else if (_selectedLine != null) {
                    _deleteSelectedLine();
                  }
                },
              ),
              IconButton(
                icon: Icon(Icons.done),
                onPressed: _toggleEditMode,
              ),
            ] else ...[
              if (dividerLines.length >= 2)
                IconButton(
                  icon: Icon(Icons.table_chart),
                  onPressed: _convertLinesToTable,
                  tooltip: 'Convert lines to table',
                ),
              IconButton(
                icon: Icon(
                  _drawingMode == DrawingMode.rectangle 
                    ? Icons.rectangle
                    : _drawingMode == DrawingMode.horizontalLine
                      ? Icons.horizontal_rule
                      : Icons.vertical_split,
                  color: _drawingMode != DrawingMode.rectangle ? Colors.blue : null,
                ),
                onPressed: _toggleDrawingMode,
                tooltip: 'Toggle drawing mode',
              ),
              IconButton(
                icon: Icon(Icons.edit),
                onPressed: _toggleEditMode,
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.file_open),
                onSelected: (value) {
                  if (value == 'new') _newFile();
                  else if (value == 'open') _openFile();
                  else if (value == 'save') _saveFile();
                  else if (value == 'pdf') _saveAsPdf();
                  else if (value == 'word') _saveAsWord();
                },
                itemBuilder: (BuildContext context) {
                  return [
                    PopupMenuItem(value: 'new', child: Text('New File')),
                    PopupMenuItem(value: 'open', child: Text('Open File')),
                    PopupMenuItem(value: 'save', child: Text('Save')),
                    PopupMenuItem(value: 'pdf', child: Text('Save as PDF')),
                    PopupMenuItem(value: 'word', child: Text('Save as Word')),
                  ];
                },
              ),
            ]
          ],
          if (_multiSelectMode) ...[
            IconButton(
              icon: Icon(Icons.space_bar),
              onPressed: _selectedElements.isNotEmpty 
                ? () => _spaceSelectedElementsEvenly()
                : null,
              tooltip: 'Space selected elements',
            ),
            IconButton(
              icon: Icon(Icons.delete, color: Colors.red),
              onPressed: _selectedElements.isNotEmpty
                ? () {
                    setState(() {
                      textElements.removeWhere((element) => _selectedElements.contains(element));
                      _selectedElements.clear();
                    });
                  }
                : null,
              tooltip: 'Delete selected',
            ),
            IconButton(
              icon: Icon(Icons.done),
              onPressed: () {
                setState(() {
                  _multiSelectMode = false;
                  _selectedElements.clear();
                });
              },
              tooltip: 'Done with multi-select',
            ),
          ]
        ],
      ),
      body: Scrollbar(
        controller: _verticalScrollController,
        thumbVisibility: true,
        trackVisibility: true,
        interactive: true,
        child: SingleChildScrollView(
          physics: NeverScrollableScrollPhysics(),
          controller: _verticalScrollController,
          scrollDirection: Axis.vertical,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 2,
            child: Padding(
              padding: EdgeInsets.all(screenPadding),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      if (showGrid)
                        CustomPaint(
                          painter: GridPainter(
                            gridSize: gridSize,
                            color: Colors.grey.withOpacity(0.3),
                          ),
                          size: Size.infinite,
                        ),
                      
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        child: GestureDetector(
                          onTapUp: (details) {
                            if (_editMode) {
                              _handleTableTap(details.localPosition);
                            } else {
                              _handleRectangleTap(details.localPosition, constraints);
                            }
                          },
                          onPanStart: (details) {
                            if (_editMode) return;
                            setState(() {
                              _startPoint = details.localPosition;
                              _currentPoint = details.localPosition;
                            });
                          },
                          onPanUpdate: (details) {
                            if (_editMode) return;
                            setState(() => _currentPoint = details.localPosition);
                          },
                          onPanEnd: (details) {
                            if (_editMode) return;
                            setState(() {
                              if (_startPoint != null && _currentPoint != null) {
                                if (_drawingMode == DrawingMode.rectangle) {
                                  final rect = Rect.fromPoints(
                                    Offset(
                                      _startPoint!.dx.clamp(screenPadding, constraints.maxWidth - screenPadding),
                                      _startPoint!.dy.clamp(screenPadding, constraints.maxHeight - screenPadding),
                                    ),
                                    Offset(
                                      _currentPoint!.dx.clamp(screenPadding, constraints.maxWidth - screenPadding),
                                      _currentPoint!.dy.clamp(screenPadding, constraints.maxHeight - screenPadding),
                                    ),
                                  );
                                
                                  // Only add rectangle if it meets minimum requirements
                                  if (rect.width.abs() >= _minRectangleWidth && 
                                      rect.height.abs() >= _minRectangleHeight) {
                                    rectangles.add(rect);
                                  }
                                      
                                } else {
                                  _handleLineDrawing(_startPoint!, _currentPoint!, constraints);
                                }
                              }
                              _startPoint = null;
                              _currentPoint = null;
                            });
                          },
                          child: CustomPaint(
                            painter: DrawingPainter(
                              rectangles: rectangles,
                              currentRect: _startPoint != null && _currentPoint != null 
                                ? (_drawingMode == DrawingMode.rectangle 
                                    ? Rect.fromPoints(
                                        Offset(
                                          _startPoint!.dx.clamp(screenPadding, constraints.maxWidth - screenPadding),
                                          _startPoint!.dy.clamp(screenPadding, constraints.maxHeight - screenPadding),
                                        ),
                                        Offset(
                                          _currentPoint!.dx.clamp(screenPadding, constraints.maxWidth - screenPadding),
                                          _currentPoint!.dy.clamp(screenPadding, constraints.maxHeight - screenPadding),
                                        ),
                                      )
                                    : null)
                                : null,
                              textElements: textElements,
                              editMode: _editMode,
                              selectedElement: _selectedElement,
                              dividerLines: dividerLines, // Add this line
                              currentLine: _startPoint != null && _currentPoint != null 
                                ? (_drawingMode != DrawingMode.rectangle 
                                    ? DividerLine(
                                        isHorizontal: _drawingMode == DrawingMode.horizontalLine,
                                        position: Offset(
                                          _startPoint!.dx.clamp(screenPadding, constraints.maxWidth - screenPadding),
                                          _startPoint!.dy.clamp(screenPadding, constraints.maxHeight - screenPadding),
                                        ),
                                        length: _drawingMode == DrawingMode.horizontalLine
                                          ? (_currentPoint!.dx - _startPoint!.dx).abs()
                                          : (_currentPoint!.dy - _startPoint!.dy).abs(),
                                      )
                                    : null)
                                : null,
                              tables: tables,
                            ),
                                      
                            child: SizedBox(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              child: GestureDetector(
                                onTapUp: (details) {
                                  if (_editMode) return;
                                  _handleRectangleTap(details.localPosition, constraints);
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      ...textElements.map((element) {
                        bool isSelected = _editMode && _selectedElement == element;
                        return Positioned(
                          left: element.position.dx,
                          top: element.position.dy,
                          child: GestureDetector(
                            onTap: () {
                              if (_editMode && _multiSelectMode) {
                                setState(() {
                                  if (_selectedElements.contains(element)) {
                                    _selectedElements.remove(element);
                                  } else {
                                    _selectedElements.add(element);
                                  }
                                });
                              } else if (_editMode && _positionEditMode) {
                                // Save previous element before switching
                                if (_selectedElement != null && _selectedElement != element) {
                                  _selectedElement!.saveCurrentState();
                                }
                                setState(() => _selectedElement = element);
                              }
                            },
                            onPanStart: (details) {
                              if (isSelected && (_positionEditMode || _multiSelectMode)) {
                                setState(() {
                                  _dragStartOffset = details.localPosition;
                                  activeGuides.clear();
                                  // In multi-select mode, select the element if not already selected
                                  if (_multiSelectMode && !_selectedElements.contains(element)) {
                                    _selectedElements.add(element);
                                  }
                                });
                              }
                            },
                            onPanUpdate: (details) {
                              if (isSelected && _positionEditMode && _dragStartOffset != null) {
                                setState(() {
                                  Offset newPosition = element.position + (details.localPosition - _dragStartOffset!);
                                  activeGuides.clear();
                                  _checkAlignments(element, newPosition, constraints);
                                  
                                  for (var guide in activeGuides) {
                                    if (guide.type == GuideType.horizontal && (newPosition.dy - guide.position).abs() < snapThreshold) {
                                      newPosition = Offset(newPosition.dx, guide.position);
                                    } else if (guide.type == GuideType.vertical && (newPosition.dx - guide.position).abs() < snapThreshold) {
                                      newPosition = Offset(guide.position, newPosition.dy);
                                    }
                                  }
                                  
                                  element.position = Offset(
                                    newPosition.dx.clamp(screenPadding, constraints.maxWidth - screenPadding - element.size.width),
                                    newPosition.dy.clamp(screenPadding, constraints.maxHeight - screenPadding - element.size.height),
                                  );
                                  _dragStartOffset = details.localPosition;
                                  _handleOverlaps(element);
                                });
                              }
                            },
                            onPanEnd: (details) {
                              setState(() {
                                activeGuides.clear();
                              });
                            },
                            child: _buildTextElement(element, isSelected, constraints),
                          ),
                        );
                      }),
            
                      ...dividerLines.map((line) {
                        bool isSelected = _editMode && _positionEditMode && _selectedLine == line;
                        final lineRect = _getLineHitRect(line);
                        
                        return Positioned.fromRect(
                          rect: lineRect,
                          child: GestureDetector(
                            onTap: () => _handleLineTap(lineRect.center),
                            onPanStart: (details) {
                              // Check if we're near a resize handle
                              final localPos = details.localPosition;
                              const handleSize = 24.0;
                              
                              if (line.isHorizontal) {
                                // Check left handle
                                if (localPos.dx < handleSize) {
                                  _handleLineResizeStart(line, Corner.left);
                                  _resizingCorner = Corner.left;
                                  return;
                                }
                                // Check right handle
                                if (localPos.dx > line.length - handleSize) {
                                  _handleLineResizeStart(line, Corner.right);
                                  _resizingCorner = Corner.right;
                                  return;
                                }
                              } else {
                                // Check top handle
                                if (localPos.dy < handleSize) {
                                  _handleLineResizeStart(line, Corner.top);
                                  _resizingCorner = Corner.top;
                                  return;
                                }
                                // Check bottom handle
                                if (localPos.dy > line.length - handleSize) {
                                  _handleLineResizeStart(line, Corner.bottom);
                                  _resizingCorner = Corner.bottom;
                                  return;
                                }
                              }
                              
                              // If not near a handle, start dragging
                              _handleLineDragStart(line, details.localPosition);
                            },
                            onPanUpdate: (details) {
                              if (_isLineResizing) {
                                _handleLineResizeUpdate(_selectedLine!, details.delta, constraints);
                              } else {
                                _handleLineDragUpdate(_selectedLine!, details.localPosition, constraints);
                              }
                            },
                            onPanEnd: (details) {
                              if (_isLineResizing) {
                                _handleLineResizeEnd();
                              } else {
                                _handleLineDragEnd();
                              }
                            },
                            child: Container(
                              color: Colors.transparent,
                              child: Stack(
                                children: [
                                  if (isSelected) ...[
                                    // Resize handles for horizontal lines
                                    if (line.isHorizontal) ...[
                                      Positioned(
                                        left: 0,
                                        top: -12,
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: Colors.blue,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        top: -12,
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: Colors.blue,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      // Resize handles for vertical lines
                                      Positioned(
                                        left: -12,
                                        top: 0,
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: Colors.blue,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: -12,
                                        bottom: 0,
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: Colors.blue,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
            
                      if (_editMode && _positionEditMode && _selectedElement != null)
                        ...activeGuides.map((guide) {
                          return Positioned(
                            left: guide.type == GuideType.vertical ? guide.position : 0,
                            top: guide.type == GuideType.horizontal ? guide.position : 0,
                            child: Container(
                              width: guide.type == GuideType.vertical ? 1 : constraints.maxWidth,
                              height: guide.type == GuideType.horizontal ? 1 : constraints.maxHeight,
                              decoration: BoxDecoration(
                                border: Border(
                                  top: guide.type == GuideType.horizontal 
                                    ? BorderSide(color: guide.color, width: 1, style: BorderStyle.solid)
                                    : BorderSide.none,
                                  left: guide.type == GuideType.vertical 
                                    ? BorderSide(color: guide.color, width: 1, style: BorderStyle.solid)
                                    : BorderSide.none,
                                ),
                              ),
                              child: guide.label != null ? Center(
                                child: Container(
                                  padding: EdgeInsets.all(2),
                                  color: guide.color.withOpacity(0.2),
                                  child: Text(
                                    guide.label!,
                                    style: TextStyle(color: guide.color, fontSize: 12),
                                  ),
                                ),
                              ) : null,
                            ),
                          );
                        }),
                      
                      if (_editMode && _positionEditMode && _selectedElement != null)
                        FormattingToolbar(
                          element: _selectedElement!,
                          onFormatChanged: (updatedElement) {
                            setState(() {});
                          },
                        ),
                    
                      if (_editMode && _selectedTable != null)
                        _buildTableEditor(_selectedTable!)
                      
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }


  void _resizeSelectedToFitContent() {
    if (_selectedElement == null) return;

    setState(() {
      // Calculate text dimensions
      final textPainter = TextPainter(
        text: TextSpan(
          text: _selectedElement!.controller.text,
          style: TextStyle(
            fontSize: _selectedElement!.fontSize,
            fontFamily: _selectedElement!.fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: null,
      )..layout(maxWidth: _selectedElement!.size.width - 8); // Account for padding
      
      // Update element size with padding (40px horizontal, 20px vertical)
      _selectedElement!.size = Size(
        (textPainter.width + 10).clamp(
          _minRectangleWidth, 
          MediaQuery.of(context).size.width - _selectedElement!.position.dx - screenPadding
        ),
        (textPainter.height + 10).clamp(
          _minRectangleHeight, 
          MediaQuery.of(context).size.height - _selectedElement!.position.dy - screenPadding
        ),
      );
    });
  }

  void _handleOverlaps(TextElement movedElement) {
    for (var element in textElements) {
      if (element == movedElement) continue;
      
      Rect movedRect = Rect.fromLTWH(
        movedElement.position.dx,
        movedElement.position.dy,
        movedElement.size.width,
        movedElement.size.height,
      );
      
      Rect elementRect = Rect.fromLTWH(
        element.position.dx,
        element.position.dy,
        element.size.width,
        element.size.height,
      );
      
      if (movedRect.overlaps(elementRect)) {
        // Calculate overlap and move the element below
        double overlapY = movedRect.bottom - elementRect.top;
        if (overlapY > 0) {
          setState(() {
            element.position = Offset(
              element.position.dx,
              element.position.dy + overlapY + 10, // Add 10px padding
            );
          });
        }
      }
    }
  }

  void _handleTableTap(Offset tapPosition) {
    if (!_editMode) return;

    // Check if tap is inside any table
    for (int i = tables.length - 1; i >= 0; i--) {
      final table = tables[i];
      final tableRect = Rect.fromLTWH(
        table.position.dx,
        table.position.dy,
        table.size.width,
        table.size.height,
      );

      if (tableRect.contains(tapPosition)) {
        setState(() {
          _selectedTable = table;
          _selectedElement = null;
          _selectedLine = null;
        });
        return;
      }
    }

    // If we get here, no table was tapped
    setState(() => _selectedTable = null);
  }

  Widget _buildTableEditor(TableElement table) {
    return Positioned(
      left: table.position.dx,
      top: table.position.dy,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTable = table;
            _selectedElement = null;
            _selectedLine = null;
          });
        },
        child: Container(
          width: table.size.width,
          height: table.size.height,
          decoration: BoxDecoration(
            border: Border.all(color: _selectedTable == table ? Colors.blue : Colors.grey, width: 2),
          ),
          child: Stack(
            children: [
              // Table cells
              for (int row = 0; row < table.rowCount; row++)
                for (int col = 0; col < table.columnCount; col++)
                  Positioned(
                    left: table.columnPositions[col],
                    top: table.rowPositions[row],
                    width: table.columnPositions[col + 1] - table.columnPositions[col],
                    height: table.rowPositions[row + 1] - table.rowPositions[row],
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedTable = table;
                          _editTableCell(table, row, col);
                        });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          color: _selectedTable == table ? Colors.white : Colors.grey[100],
                        ),
                        padding: EdgeInsets.all(4),
                        child: Center(
                          child: Text(
                            table.cells[row][col],
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  void _editTableCell(TableElement table, int row, int col) {
    final controller = TextEditingController(text: table.cells[row][col]);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Cell (${row+1},${col+1})'),
        content: TextField(
          controller: controller,
          maxLines: null,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text('Save'),
            onPressed: () {
              setState(() {
                table.cells[row][col] = controller.text;
              });
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
  
  void _convertLinesToTable() {
    // Find all horizontal and vertical lines that intersect
    final horizontalLines = dividerLines.where((line) => line.isHorizontal).toList();
    final verticalLines = dividerLines.where((line) => !line.isHorizontal).toList();

    if (horizontalLines.isEmpty || verticalLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Need at least one horizontal and one vertical line to create a table')),
      );
      return;
    }

    // Sort lines by position
    horizontalLines.sort((a, b) => a.position.dy.compareTo(b.position.dy));
    verticalLines.sort((a, b) => a.position.dx.compareTo(b.position.dx));

    // Calculate row heights (equal distribution)
    final double totalHeight = horizontalLines.last.position.dy + horizontalLines.last.length - 
                            horizontalLines.first.position.dy;
    final double rowHeight = totalHeight / horizontalLines.length;

    // Calculate column widths (equal distribution)
    final double totalWidth = verticalLines.last.position.dx + verticalLines.last.length - 
                            verticalLines.first.position.dx;
    final double columnWidth = totalWidth / verticalLines.length;

    // Create row and column positions
    final rowPositions = List<double>.generate(
      horizontalLines.length + 1,
      (i) => horizontalLines.first.position.dy + (i * rowHeight),
    );
    
    final columnPositions = List<double>.generate(
      verticalLines.length + 1,
      (i) => verticalLines.first.position.dx + (i * columnWidth),
    );

    // Initialize empty cells
    final cells = List.generate(
      horizontalLines.length,
      (_) => List.filled(verticalLines.length, ''),
    );

  // Calculate table position and size
  final position = Offset(
    verticalLines.first.position.dx,
    horizontalLines.first.position.dy,
  );
  
  final size = Size(totalWidth, totalHeight);

  setState(() {
    // Remove the lines that were converted to table
    dividerLines.removeWhere((line) => horizontalLines.contains(line) || verticalLines.contains(line));
    
    tables.add(TableElement(
      columnPositions: columnPositions,
      rowPositions: rowPositions,
      cells: cells,
      position: position,
      size: size,
    ));
    
    _selectedTable = tables.last;
    _selectedElement = null;
    _selectedLine = null;
  });
}

  (List<DividerLine>, List<DividerLine>) _findIntersectingLines(
    List<DividerLine> horizontalLines, 
    List<DividerLine> verticalLines
  ) {
    final validHorizontal = <DividerLine>[];
    final validVertical = <DividerLine>[];

    for (final hLine in horizontalLines) {
      for (final vLine in verticalLines) {
        // Check if lines intersect
        if (_doLinesIntersect(hLine, vLine)) {
          if (!validHorizontal.contains(hLine)) validHorizontal.add(hLine);
          if (!validVertical.contains(vLine)) validVertical.add(vLine);
        }
      }
    }

    return (validHorizontal, validVertical);
  }

  bool _doLinesIntersect(DividerLine hLine, DividerLine vLine) {
    // Horizontal line runs from (x1,y) to (x2,y)
    // Vertical line runs from (x,y1) to (x,y2)
    
    // Check if vertical line x is between horizontal line's x range
    final xOverlap = vLine.position.dx >= hLine.position.dx && 
                    vLine.position.dx <= hLine.position.dx + hLine.length;
    
    // Check if horizontal line y is between vertical line's y range
    final yOverlap = hLine.position.dy >= vLine.position.dy && 
                    hLine.position.dy <= vLine.position.dy + vLine.length;
    
    return xOverlap && yOverlap;
  }

  TableElement _createTableFromLines(
    List<DividerLine> horizontalLines, 
    List<DividerLine> verticalLines
  ) {
    // Sort lines by position
    horizontalLines.sort((a, b) => a.position.dy.compareTo(b.position.dy));
    verticalLines.sort((a, b) => a.position.dx.compareTo(b.position.dx));

    // Extract row and column positions
    final rowPositions = [
      horizontalLines.first.position.dy,
      ...horizontalLines.map((line) => line.position.dy + line.length),
    ];
    
    final columnPositions = [
      verticalLines.first.position.dx,
      ...verticalLines.map((line) => line.position.dx + line.length),
    ];

    // Calculate table position and size
    final position = Offset(
      verticalLines.first.position.dx,
      horizontalLines.first.position.dy,
    );
    
    final size = Size(
      verticalLines.last.position.dx + verticalLines.last.length - position.dx,
      horizontalLines.last.position.dy + horizontalLines.last.length - position.dy,
    );

    // Initialize empty cells
    final cells = List.generate(
      rowPositions.length - 1,
      (_) => List.filled(columnPositions.length - 1, ''),
    );

    return TableElement(
      columnPositions: columnPositions,
      rowPositions: rowPositions,
      cells: cells,
      position: position,
      size: size,
    );
  }

  void _spaceSelectedElementsEvenly() {
    if (_selectedElements.length < 2) return;

    setState(() {
      const double fixedSpacing = 10.0; // Fixed 10px spacing between elements
      
      // Sort selected elements by their current vertical position
      final sortedElements = _selectedElements.toList()
        ..sort((a, b) => a.position.dy.compareTo(b.position.dy));

      // Calculate starting position (keeping the top element's position)
      double currentY = sortedElements.first.position.dy;
      
      // Position elements with fixed spacing
      for (var element in sortedElements) {
        element.position = Offset(element.position.dx, currentY);
        currentY += element.size.height + fixedSpacing;
      }
    });
  }

  void _toggleMultiSelectMode() {
    setState(() {
      _multiSelectMode = !_multiSelectMode;
      if (!_multiSelectMode) {
        _selectedElements.clear();
      }
      // Clear other modes when entering multi-select
      _contentEditMode = false;
      _positionEditMode = false;
      _selectedElement = null;
      _selectedLine = null;
    });
  }

  void _saveState() {
    // Remove any states after current index (for redo)
    if (_currentStateIndex < _stateHistory.length - 1) {
      _stateHistory = _stateHistory.sublist(0, _currentStateIndex + 1);
    }
    
    _stateHistory.add(_DrawingState(
      rectangles: List.from(rectangles),
      textElements: textElements.map((e) => TextElement(
        position: e.position,
        size: e.size,
        controller: TextEditingController(text: e.controller.text),
        fontSize: e.fontSize,
        alignment: e.alignment,
        fontFamily: e.fontFamily,
      )).toList(),
      dividerLines: List.from(dividerLines), tables: List.from(tables)
    ));
    
    _currentStateIndex = _stateHistory.length - 1;
    
    // Limit history size
    if (_stateHistory.length > 50) {
      _stateHistory.removeAt(0);
      _currentStateIndex--;
    }
  }

  void _undo() {
    if (_currentStateIndex <= 0) return;
    
    setState(() {
      _currentStateIndex--;
      final state = _stateHistory[_currentStateIndex];
      
      rectangles.clear();
      rectangles.addAll(state.rectangles);
      
      textElements.clear();
      textElements.addAll(state.textElements.map((e) => TextElement(
        position: e.position,
        size: e.size,
        controller: TextEditingController(text: e.controller.text),
        fontSize: e.fontSize,
        alignment: e.alignment,
        fontFamily: e.fontFamily,
      )));
      
      dividerLines.clear();
      dividerLines.addAll(state.dividerLines);
    });
  }

  void _redo() {
    if (_currentStateIndex >= _stateHistory.length - 1) return;
    
    setState(() {
      _currentStateIndex++;
      final state = _stateHistory[_currentStateIndex];
      
      rectangles.clear();
      rectangles.addAll(state.rectangles);
      
      textElements.clear();
      textElements.addAll(state.textElements.map((e) => TextElement(
        position: e.position,
        size: e.size,
        controller: TextEditingController(text: e.controller.text),
        fontSize: e.fontSize,
        alignment: e.alignment,
        fontFamily: e.fontFamily,
      )));
      
      dividerLines.clear();
      dividerLines.addAll(state.dividerLines);
    });
  }

  Future<void> _changeSelectedLineColor() async {
    if (_selectedLine == null) return;

    Color? newColor = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Line Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _selectedLine!.color,
            onColorChanged: (color) {
              _selectedLine!.color = color;
            },
            showLabel: true,
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text('OK'),
            onPressed: () => Navigator.pop(context, _selectedLine!.color),
          ),
        ],
      ),
    );

    if (newColor != null) {
      setState(() {
        final index = dividerLines.indexOf(_selectedLine!);
        if (index != -1) {
          dividerLines[index] = _selectedLine!.copyWith(color: newColor);
          _saveState();
        }
      });
    }
  }

  String? _currentFilePath;

  Future<void> _saveFile() async {
    try {
      // Force any active text field to save its changes
      if (_selectedElement != null && _contentEditMode) {
        _selectedElement!._updateSpansFromText();
        FocusManager.instance.primaryFocus?.unfocus(); // Save any focused text field
      }

      // Create a fresh serialization of current state
      final fileContent = jsonEncode(_serializeData());
      final bytes = Uint8List.fromList(utf8.encode(fileContent));

      if (_currentFilePath != null) {
        // Create a backup before overwriting
        final backupPath = '${_currentFilePath!}.bak';
        if (await File(_currentFilePath!).exists()) {
          await File(_currentFilePath!).copy(backupPath);
        }

        // Write the new file
        final file = File(_currentFilePath!);
        await file.writeAsBytes(bytes, flush: true); // Force flush to disk

        // Verify the write was successful
        final savedContent = await file.readAsString();
        if (savedContent != fileContent) {
          throw Exception('File write verification failed');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File saved successfully')),
        );
      } else {
        // For new files, use the save dialog
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Save your document',
          fileName: 'document.json',
          allowedExtensions: ['json'],
          type: FileType.custom,
          bytes: bytes,
        );

        if (path != null) {
          _currentFilePath = path;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File saved successfully')),
          );
        }
      }
    } catch (e, stack) {
      print('Error saving file: $e\n$stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save file: ${e.toString()}')),
      );
    }
  }

  void _newFile() {
    setState(() {
      rectangles.clear();
      textElements.clear();
      dividerLines.clear();
      _selectedElement = null;
      _selectedLine = null;
      _currentFilePath = null; // Reset the path
    });
  }

  Future<void> _openFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null) {
        final file = File(result.files.single.path!);
        String content = await file.readAsString();

        // Clean the content - remove any invalid characters
        content = content.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
        
        // Try to parse the JSON
        final jsonData = jsonDecode(content) as Map<String, dynamic>;

        // Validate the basic structure
        if (jsonData['textElements'] == null || 
            jsonData['rectangles'] == null || 
            jsonData['dividerLines'] == null) {
          throw FormatException('Invalid file format');
        }

        setState(() {
          _currentFilePath = file.path;
          _loadDataFromJson(jsonData);
        });
      }
    } on FormatException catch (e) {
      print('JSON Format Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid file format. Please select a valid document file.')),
      );
    } on PlatformException catch (e) {
      print('File Picker Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error accessing file: ${e.message}')),
      );
    } catch (e, stack) {
      print('Error opening file: $e\n$stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening file. The file may be corrupted.')),
      );
    }
  }

  void _loadDataFromJson(Map<String, dynamic> jsonData) {
    rectangles = (jsonData['rectangles'] as List).map((r) => Rect.fromLTWH(
      (r['left'] ?? 0).toDouble(),
      (r['top'] ?? 0).toDouble(),
      (r['width'] ?? 100).toDouble(),
      (r['height'] ?? 50).toDouble(),
    )).toList();

    textElements = (jsonData['textElements'] as List).map((te) {
      final element = TextElement(
        position: Offset(
          (te['position']['dx'] ?? 0).toDouble(),
          (te['position']['dy'] ?? 0).toDouble(),
        ),
        size: Size(
          (te['size']['width'] ?? 100).toDouble(),
          (te['size']['height'] ?? 50).toDouble(),
        ),
        controller: TextEditingController(text: te['text'] ?? ''),
        fontSize: (te['fontSize'] ?? 16).toDouble(),
        alignment: TextAlign.values[(te['alignment'] as int?) ?? 0],
        fontFamily: te['fontFamily']?.toString() ?? 'Arial',
      );

      // Load text spans if they exist
      if (te['textSpans'] != null) {
        element.textSpans = (te['textSpans'] as List).map((span) {
          final style = span['style'] != null ? TextStyle(
            fontWeight: span['style']['fontWeight'] != null 
              ? FontWeight.values[span['style']['fontWeight']]
              : FontWeight.normal,
            fontStyle: span['style']['fontStyle'] != null
              ? FontStyle.values[span['style']['fontStyle']]
              : FontStyle.normal,
            fontSize: (span['style']['fontSize'] ?? element.fontSize).toDouble(),
            fontFamily: span['style']['fontFamily']?.toString() ?? element.fontFamily,
            color: span['style']['color'] != null
              ? Color(span['style']['color'] as int)
              : Colors.black,
          ) : null;

          return TextSpan(
            text: span['text']?.toString() ?? '',
            style: style,
          );
        }).toList();
      }

      return element;
    }).toList();

    dividerLines = (jsonData['dividerLines'] as List).map((dl) {
      return DividerLine(
        isHorizontal: dl['isHorizontal'] ?? true,
        position: Offset(
          (dl['position']['dx'] ?? 0).toDouble(),
          (dl['position']['dy'] ?? 0).toDouble(),
        ),
        length: (dl['length'] ?? 100).toDouble(),
        color: Color(dl['color'] as int? ?? Colors.grey.value),
      );
    }).toList();
  }

  PdfColor _getPdfTextColor(TextElement element) {
    // Default to black if no color is specified
    Color textColor = Colors.black;
    
    // Check if any span has a specific color
    for (var span in element.textSpans) {
      if (span.style?.color != null) {
        textColor = span.style!.color!;
        break; // Use the first color found
      }
    }
    
    // Convert Flutter Color to PDF Color
    return PdfColor.fromInt(textColor.value);
  }

  pw.TextAlign _getPdfTextAlign(TextAlign align) {
    switch (align) {
      case TextAlign.left: return pw.TextAlign.left;
      case TextAlign.right: return pw.TextAlign.right;
      case TextAlign.center: return pw.TextAlign.center;
      case TextAlign.justify: return pw.TextAlign.justify;
      default: return pw.TextAlign.left;
    }
  }

  pw.Font _getPdfFont(String fontFamily) {
    switch (fontFamily.toLowerCase()) {
      case 'times new roman':
        return pw.Font.times();
      case 'courier new':
        return pw.Font.courier();
      default: // Default to helvetica
        return pw.Font.helvetica();
    }
  }
  
  Future<void> _saveAsPdf() async {
    try {
      final pdf = pw.Document();

      pdf.addPage(pw.Page(
        margin: pw.EdgeInsets.all(16),
        build: (pw.Context context) {
          return pw.Column(
            children: [
              for (var element in textElements)
                pw.Container(
                  width: 200,
                  height: element.size.height,
                  child: _buildPdfTextWidget(element),
                ),
              
              for (var line in dividerLines)
                pw.Container(
                  width: line.isHorizontal ? line.length : 1,
                  height: line.isHorizontal ? 1 : line.length,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.black,
                  ),
                  margin: pw.EdgeInsets.only(
                    left: line.position.dx,
                    top: line.position.dy,
                  ),
                ),
            ],
          );
        },
      ));

      final output = await getTemporaryDirectory();
      final file = File('${output.path}/document.pdf');
      await file.writeAsBytes(await pdf.save());
      
      await Share.shareXFiles([XFile(file.path)], text: 'Here is the PDF export');
    } catch (e) {
      print('Error creating PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating PDF: $e')),
      );
    }
  }

  pw.Widget _buildPdfTextWidget(TextElement element) {
    if (element.textSpans.length > 1) {
      return pw.RichText(
        text: pw.TextSpan(
          children: [
            for (var span in element.textSpans)
              pw.TextSpan(
                text: _cleanPdfText(span.text ?? ''),
                style: pw.TextStyle(
                  font: _getPdfFont(element.fontFamily),
                  fontSize: span.style?.fontSize ?? element.fontSize,
                  fontWeight: span.style?.fontWeight == FontWeight.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  fontStyle: span.style?.fontStyle == FontStyle.italic ? pw.FontStyle.italic : pw.FontStyle.normal,
                  color: span.style?.color != null ? PdfColor.fromInt(span.style!.color!.value) : PdfColors.black,
                ),
              ),
          ],
        ),
        textAlign: _getPdfTextAlign(element.alignment),
      );
    } else {
      // Simple text with uniform styling
      return pw.Text(
        _cleanPdfText(element.controller.text),
        style: pw.TextStyle(
          font: _getPdfFont(element.fontFamily),
          fontSize: element.fontSize,
          fontWeight: _hasBold(element) ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontStyle: _hasItalic(element) ? pw.FontStyle.italic : pw.FontStyle.normal,
          color: _getPdfTextColor(element),
        ),
        textAlign: _getPdfTextAlign(element.alignment),
      );
    }
  }

  String _cleanPdfText(String text) {
    // Replace problematic characters with PDF-safe equivalents
    return text
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll("‘", "'")
        .replaceAll("’", "'")
        .replaceAll("–", "-")
        .replaceAll("—", "-")
        .replaceAll("•", "•")
        .replaceAll('\u2022', '•')
        .replaceAll('\u25CF', '•')
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ''); 
  }

  bool _hasBold(TextElement element) {
    for (var span in element.textSpans) {
      if (span.style?.fontWeight == FontWeight.bold) {
        return true;
      }
    }
    return false;
  }

  bool _hasItalic(TextElement element) {
    for (var span in element.textSpans) {
      if (span.style?.fontStyle == FontStyle.italic) {
        return true;
      }
    }
    return false;
  }

  Future<void> _saveAsWord() async {
    try {
      final data = await rootBundle.load('assets/template.docx');
      final bytes = data.buffer.asUint8List();

      final docx = await DocxTemplate.fromBytes(bytes);

      // Prepare the content for the Word document
      // final content = Content();
      
      // Add all text elements to the document
      final textContent = textElements.map((element) {
        // Extract the text with formatting
        String text = element.controller.text;
        
        // Apply basic formatting
        String formattedText = text;
        if (_hasBold(element)) formattedText = '<b>$formattedText</b>';
        if (_hasItalic(element)) formattedText = '<i>$formattedText</i>';
        
        // Add paragraph with alignment
        String alignTag = '';
        switch (element.alignment) {
          case TextAlign.center:
            alignTag = '<center>';
            break;
          case TextAlign.right:
            alignTag = '<right>';
            break;
          case TextAlign.justify:
            alignTag = '<justify>';
            break;
          default:
            alignTag = '<left>';
        }
        
        // return '$alignTag$formattedText</${alignTag.substring(1)}';
        return '$text';
      }).join('\n\n');

      // Add divider lines as horizontal rules
      final linesContent = dividerLines.where((line) => line.isHorizontal).map((_) => '<hr/>').join('\n');
      
      // Combine all content
      final content = Content();
      content.add(TextContent('title', 'Exported Document'));
      // content.add(TextContent('content', '$textContent'));

      // final content = Content(
      // text: [
      //     TextContent('title', 'Exported Document'),
      //     TextContent('content', '$textContent\n$linesContent'),
      //   ],
      // );
      print('Content created successfully.');


      
      // Generate the document
      final generatedBytes = await docx.generate(content);
      
      // Save the file
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/document.docx');
      if (generatedBytes != null) await file.writeAsBytes(generatedBytes);

      // final d = await docx.generate(c);
      // final of = File('generated.docx');
      // if (d != null) await of.writeAsBytes(d);
      
      // Share the file
      await Share.shareXFiles([XFile(file.path)], text: 'Here is the Word export');
    } catch (e) {
      print('Error creating Word document: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating Word document: $e')),
      );
    }
  }

  Map<String, dynamic> _serializeData() {
    return {
      'rectangles': rectangles.map((r) => {
        'left': r.left,
        'top': r.top,
        'width': r.width,
        'height': r.height,
      }).toList(),
      'textElements': textElements.map((te) {
        // Clean the text before saving
        String cleanText = te.controller.text
          .replaceAll('“', '"')
          .replaceAll('”', '"')
          .replaceAll("‘", "'")
          .replaceAll("’", "'")
          .replaceAll("–", "-")
          .replaceAll("—", "-")
          .replaceAll("•", "•")
          .replaceAll('\u2022', '•')
          .replaceAll('\u25CF', '•');
        
        return {
          'position': {'dx': te.position.dx, 'dy': te.position.dy},
          'size': {'width': te.size.width, 'height': te.size.height},
          'text': cleanText,
          'alignment': te.alignment.index,
          'fontSize': te.fontSize,
          'fontFamily': te.fontFamily,
          'showBullets': te.showBullets,
          'textSpans': te.textSpans.map((span) {
            return {
              'text': span.text,
              'style': {
                'fontWeight': span.style?.fontWeight?.index,
                'fontStyle': span.style?.fontStyle?.index,
                'color': span.style?.color?.value,
              },
            };
          }).toList(),
        };
      }).toList(),
      'dividerLines': dividerLines.map((dl) => {
        'isHorizontal': dl.isHorizontal,
        'position': {'dx': dl.position.dx, 'dy': dl.position.dy},
        'length': dl.length,
        'color': dl.color.value, // Save color
      }).toList(),
    };
  }

  void _handleLineTap(Offset tapPosition) {
    if (!_editMode || !_positionEditMode) return;

    // Check if we tapped on a line (starting from top-most)
    for (int i = dividerLines.length - 1; i >= 0; i--) {
      final line = dividerLines[i];
      final lineRect = _getLineHitRect(line);
      
      if (lineRect.contains(tapPosition)) {
        setState(() {
          _selectedLine = line;
          _selectedElement = null; // Deselect any text element
        });
        return;
      }
    }
    
    // If we get here, no line was tapped
    setState(() => _selectedLine = null);
  }

  Rect _getLineHitRect(DividerLine line) {
    const hitPadding = 8.0;
    if (line.isHorizontal) {
      return Rect.fromLTRB(
        line.position.dx - hitPadding,
        line.position.dy - hitPadding,
        line.position.dx + line.length + hitPadding,
        line.position.dy + hitPadding,
      );
    } else {
      return Rect.fromLTRB(
        line.position.dx - hitPadding,
        line.position.dy - hitPadding,
        line.position.dx + hitPadding,
        line.position.dy + line.length + hitPadding,
      );
    }
  }

  void _deleteSelectedLine() {
    if (_selectedLine != null) {
      setState(() {
        dividerLines.remove(_selectedLine);
        _selectedLine = null;
      });
    }
  }

  void _handleLineDragStart(DividerLine line, Offset localPosition) {
    setState(() {
      _lineDragStartOffset = localPosition;
      _selectedLine = line;
      activeGuides.clear();
    });
  }

  void _handleLineDragUpdate(DividerLine line, Offset localPosition, BoxConstraints constraints) {
    if (_lineDragStartOffset == null) return;

    setState(() {
      final delta = localPosition - _lineDragStartOffset!;
      Offset newPosition = line.position + delta;
      
      // Constrain to screen bounds - allow movement in both axes
      newPosition = Offset(
        newPosition.dx.clamp(screenPadding, constraints.maxWidth - screenPadding - (line.isHorizontal ? line.length : 0)),
        newPosition.dy.clamp(screenPadding, constraints.maxHeight - screenPadding - (line.isHorizontal ? 0 : line.length)),
      );
      
      // Check for alignment guides
      activeGuides.clear();
      _checkLineAlignments(line, newPosition, constraints);
      
      // Apply snapping if near a guide
      for (var guide in activeGuides) {
        if (guide.type == GuideType.horizontal && (newPosition.dy - guide.position).abs() < snapThreshold) {
          newPosition = Offset(newPosition.dx, guide.position);
        }
        if (guide.type == GuideType.vertical && (newPosition.dx - guide.position).abs() < snapThreshold) {
          newPosition = Offset(guide.position, newPosition.dy);
        }
      }
      
      // Find the index safely
      final index = dividerLines.indexOf(line);
      if (index == -1) return; // Line not found
      
      // Update the line position
      dividerLines[index] = DividerLine(
        isHorizontal: line.isHorizontal,
        position: newPosition,
        length: line.length,
      );
      
      _selectedLine = dividerLines[index];
      _lineDragStartOffset = localPosition;
    });
    }

  void _handleLineDragEnd() {
    setState(() {
      _lineDragStartOffset = null;
      activeGuides.clear();
    });
  }

  void _checkLineAlignments(DividerLine movingLine, Offset newPosition, BoxConstraints constraints) {
    // Check alignment with other lines
    for (var line in dividerLines) {
      if (line == movingLine) continue;
      
      if (movingLine.isHorizontal && line.isHorizontal) {
        // Horizontal line aligning with other horizontal lines
        if ((newPosition.dy - line.position.dy).abs() < 20) {
          activeGuides.add(AlignmentGuide(
            GuideType.horizontal,
            line.position.dy,
            label: "Align",
            color: Colors.blue,
          ));
        }
      } else if (!movingLine.isHorizontal && !line.isHorizontal) {
        // Vertical line aligning with other vertical lines
        if ((newPosition.dx - line.position.dx).abs() < 20) {
          activeGuides.add(AlignmentGuide(
            GuideType.vertical,
            line.position.dx,
            label: "Align",
            color: Colors.blue,
          ));
        }
      }
    }
    
    // Check screen alignment
    if (movingLine.isHorizontal) {
      // Horizontal line aligning with screen edges
      if ((newPosition.dy - screenPadding).abs() < 20) {
        activeGuides.add(AlignmentGuide(
          GuideType.horizontal,
          screenPadding,
          label: "Top Margin",
          color: Colors.purple,
        ));
      }
      
      if ((newPosition.dy - (constraints.maxHeight - screenPadding)).abs() < 20) {
        activeGuides.add(AlignmentGuide(
          GuideType.horizontal,
          constraints.maxHeight - screenPadding,
          label: "Bottom Margin",
          color: Colors.purple,
        ));
      }
      
      // Center alignment
      if ((newPosition.dy - constraints.maxHeight / 2).abs() < 20) {
        activeGuides.add(AlignmentGuide(
          GuideType.horizontal,
          constraints.maxHeight / 2,
          label: "Center",
          color: Colors.green,
        ));
      }
    } else {
      // Vertical line aligning with screen edges
      if ((newPosition.dx - screenPadding).abs() < 20) {
        activeGuides.add(AlignmentGuide(
          GuideType.vertical,
          screenPadding,
          label: "Left Margin",
          color: Colors.purple,
        ));
      }
      
      if ((newPosition.dx - (constraints.maxWidth - screenPadding)).abs() < 20) {
        activeGuides.add(AlignmentGuide(
          GuideType.vertical,
          constraints.maxWidth - screenPadding,
          label: "Right Margin",
          color: Colors.purple,
        ));
      }
      
      // Center alignment
      if ((newPosition.dx - constraints.maxWidth / 2).abs() < 20) {
        activeGuides.add(AlignmentGuide(
          GuideType.vertical,
          constraints.maxWidth / 2,
          label: "Center",
          color: Colors.green,
        ));
      }
    }
  }

  void _handleLineResizeStart(DividerLine line, Corner corner) {
    setState(() {
      _isLineResizing = true;
      _selectedLine = line;
    });
  }

  void _handleLineResizeUpdate(DividerLine line, Offset delta, BoxConstraints constraints) {
    setState(() {
      final index = dividerLines.indexOf(line);
      if (index == -1) return; // Line not found
      
      double newLength = line.length;
      Offset newPosition = line.position;
      
      if (line.isHorizontal) {
        if (_resizingCorner == Corner.right) {
          newLength = (line.length + delta.dx).clamp(50, constraints.maxWidth - line.position.dx - screenPadding);
        } else if (_resizingCorner == Corner.left) {
          final newStartX = (line.position.dx + delta.dx).clamp(screenPadding, line.position.dx + line.length - 50);
          newLength = line.length - (newStartX - line.position.dx);
          newPosition = Offset(newStartX, line.position.dy);
        }
      } else {
        if (_resizingCorner == Corner.bottom) {
          newLength = (line.length + delta.dy).clamp(50, constraints.maxHeight - line.position.dy - screenPadding);
        } else if (_resizingCorner == Corner.top) {
          final newStartY = (line.position.dy + delta.dy).clamp(screenPadding, line.position.dy + line.length - 50);
          newLength = line.length - (newStartY - line.position.dy);
          newPosition = Offset(line.position.dx, newStartY);
        }
      }
      
      dividerLines[index] = DividerLine(
        isHorizontal: line.isHorizontal,
        position: newPosition,
        length: newLength,
      );
      _selectedLine = dividerLines[index];
    });
  }

  void _handleLineResizeEnd() {
    setState(() {
      _isLineResizing = false;
      _resizingCorner = Corner.none;
    });
  }

  void _toggleDrawingMode() {
    setState(() {
      _drawingMode = _drawingMode == DrawingMode.rectangle 
        ? DrawingMode.horizontalLine 
        : _drawingMode == DrawingMode.horizontalLine
          ? DrawingMode.verticalLine
          : DrawingMode.rectangle;
    });
  }

  void _handleLineDrawing(Offset startPoint, Offset endPoint, BoxConstraints constraints) {
    final isHorizontal = _drawingMode == DrawingMode.horizontalLine;
    
    // Calculate position constrained within screen bounds
    final position = Offset(
      startPoint.dx.clamp(screenPadding, constraints.maxWidth - screenPadding),
      startPoint.dy.clamp(screenPadding, constraints.maxHeight - screenPadding),
    );
    
    // Calculate length constrained within screen bounds
    double length = isHorizontal 
      ? (endPoint.dx - startPoint.dx).abs()
      : (endPoint.dy - startPoint.dy).abs();
    
    // Constrain length to stay within screen bounds
    if (isHorizontal) {
      length = min(length, constraints.maxWidth - screenPadding - position.dx);
    } else {
      length = min(length, constraints.maxHeight - screenPadding - position.dy);
    }
    
    // Minimum length for lines
    if (length < 50) return;
    
    setState(() {
      dividerLines.add(DividerLine(
        isHorizontal: isHorizontal,
        position: position,
        length: length,
      ));
    });
  }

  void _cleanUpInvalidRectangles() {
    setState(() {
      rectangles.removeWhere((rect) {
        return rect.width.abs() < _minRectangleWidth || 
              rect.height.abs() < _minRectangleHeight;
      });
    });
  }

  void _spaceElementsEvenly() {
    if (textElements.length < 2) return;

    setState(() {
      // Sort elements by their current vertical position
      textElements.sort((a, b) => a.position.dy.compareTo(b.position.dy));

      // Calculate total height available for spacing
      final double screenPadding = 20.0;
      final double totalHeight = MediaQuery.of(context).size.height - (2 * screenPadding);
      
      // Calculate total height of all elements
      double elementsHeight = 0;
      for (var element in textElements) {
        elementsHeight += element.size.height;
      }
      
      // Calculate available space between elements
      double availableSpace = totalHeight - elementsHeight;
      double spacing = availableSpace / (textElements.length - 1);
      
      // Position elements with even spacing
      double currentY = screenPadding;
      for (var element in textElements) {
        element.position = Offset(element.position.dx, currentY);
        currentY += element.size.height + spacing;
      }

      // Also consider horizontal alignment if needed
      // You could add similar logic for horizontal spacing if desired
    });
  }

  void _handleRectangleTap(Offset tapPosition, BoxConstraints constraints) async {
    // Check if tap is inside any rectangle (starting from top-most)
    for (int i = rectangles.length - 1; i >= 0; i--) {
      final rect = rectangles[i];
      
      // Skip if tap isn't inside this rectangle
      if (!rect.contains(tapPosition)) continue;
      
      // Skip if rectangle is too small to be converted
      if (rect.width.abs() < _minRectangleWidth || 
          rect.height.abs() < _minRectangleHeight) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rectangle too small to convert to text box'),
            duration: Duration(seconds: 1),
          ),
        );
        continue;
      }
      
      // Check if this rectangle overlaps with any existing text element
      bool overlapsWithExisting = false;
      for (var element in textElements) {
        Rect elementRect = Rect.fromLTWH(
          element.position.dx, 
          element.position.dy, 
          element.size.width, 
          element.size.height
        );
        
        if (rect.overlaps(elementRect)) {
          overlapsWithExisting = true;
          break;
        }
      }
      
      if (overlapsWithExisting) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Area already contains text'),
            duration: Duration(seconds: 1),
          ),
        );
        continue;
      }
      
      // If we get here, we have a valid rectangle to convert
      String? content = await showDialog<String>(
        context: context,
        builder: (context) => TextInputDialog(),
      );
      
      if (content != null && content.isNotEmpty) {
        // Calculate text dimensions with wrapping
        final textPainter = TextPainter(
          text: TextSpan(
            text: content,
            style: TextStyle(fontSize: 16),
          ),
          textDirection: TextDirection.ltr,
          maxLines: null,
        )..layout(maxWidth: rect.width - 40); // Account for padding
        
        // Calculate new dimensions with padding (20px horizontal, 10px vertical)
        final newWidth = textPainter.width + 40;
        final newHeight = textPainter.height + 20;
        
        // Ensure the new dimensions are within bounds
        final adjustedWidth = newWidth.clamp(_minRectangleWidth, rect.width);
        final adjustedHeight = newHeight.clamp(_minRectangleHeight, double.infinity);
        
        setState(() {
          textElements.add(TextElement(
            position: Offset(rect.left, rect.top),
            size: Size(adjustedWidth, adjustedHeight),
            controller: TextEditingController(text: content),
          ));
          rectangles.removeAt(i);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Text box created'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      
      return;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tap inside a rectangle to convert it to text'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Widget _buildTextElement(TextElement element, bool isSelected, BoxConstraints constraints) {
    return Stack(
      children: [
        Container(
          width: element.size.width,
          height: element.size.height,
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected 
                ? Colors.blue 
                : _multiSelectMode && _selectedElements.contains(element)
                  ? Colors.green
                  : Colors.transparent,
              width: 2.0,
            ),
            color: _contentEditMode ? Colors.white.withOpacity(0.9) : Colors.transparent,
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: _contentEditMode && element == _selectedElement
              ? TextField(
                  controller: element.controller,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: TextStyle(
                    fontSize: element.fontSize,
                    color: Colors.black,
                    fontFamily: element.fontFamily,
                  ),
                  textAlign: element.alignment,
                  maxLines: null,
                  onChanged: (text) {
                    element._updateSpansFromText();
                    if (_contentEditMode) {
                      // Calculate text dimensions
                      final textPainter = TextPainter(
                        text: TextSpan(
                          text: text,
                          style: TextStyle(
                            fontSize: element.fontSize,
                            fontFamily: element.fontFamily,
                          ),
                        ),
                        textDirection: TextDirection.ltr,
                        maxLines: null,
                      )..layout(maxWidth: element.size.width - 8); // Account for padding
                      
                      // Update element size with state management
                      setState(() {
                        element.size = Size(
                          (textPainter.width + 40).clamp(
                            _minRectangleWidth, 
                            constraints.maxWidth - element.position.dx - screenPadding
                          ),
                          (textPainter.height + 20).clamp(
                            _minRectangleHeight, 
                            constraints.maxHeight - element.position.dy - screenPadding
                          ),
                        );
                      });
                    }
                  },
                )
              : RichText(
                  text: TextSpan(
                    children: element.textSpans,
                    style: TextStyle(
                      fontSize: element.fontSize,
                      color: Colors.black,
                      fontFamily: element.fontFamily,
                    ),
                  ),
                  textAlign: element.alignment,
                ),
          ),
        ),
        
        if (isSelected && _positionEditMode) ...[
          _buildResizeHandle(element, Corner.top, constraints),
          _buildResizeHandle(element, Corner.right, constraints),
          _buildResizeHandle(element, Corner.bottom, constraints),
          _buildResizeHandle(element, Corner.left, constraints),
        ],
      ],
    );
  }

  Widget _buildResizeHandle(TextElement element, Corner corner, BoxConstraints constraints) {
    return Positioned(
      left: corner == Corner.left ? 0 : null,
      right: corner == Corner.right ? 0 : null,
      top: corner == Corner.top ? 0 : null,
      bottom: corner == Corner.bottom ? 0 : null,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _isResizing = true;
            _resizingCorner = corner;
            _dragStartOffset = details.localPosition;
          });
        },
        onPanUpdate: (details) {
          if (_isResizing && _dragStartOffset != null) {
            setState(() {
              final delta = details.localPosition - _dragStartOffset!;
              
              switch (corner) {
                case Corner.left:
                  final newWidth = element.size.width - delta.dx;
                  if (newWidth > 50 && 
                      element.position.dx + delta.dx >= screenPadding) {
                    element.position += Offset(delta.dx, 0);
                    element.size = Size(newWidth, element.size.height);
                  }
                  break;
                case Corner.right:
                  final newWidth = element.size.width + delta.dx;
                  if (newWidth > 50 && 
                      element.position.dx + newWidth <= constraints.maxWidth - screenPadding) {
                    element.size = Size(newWidth, element.size.height);
                  }
                  break;
                case Corner.top:
                  final newHeight = element.size.height - delta.dy;
                  if (newHeight > 30 && 
                      element.position.dy + delta.dy >= screenPadding) {
                    element.position += Offset(0, delta.dy);
                    element.size = Size(element.size.width, newHeight);
                  }
                  break;
                case Corner.bottom:
                  final newHeight = element.size.height + delta.dy;
                  if (newHeight > 30 && 
                      element.position.dy + newHeight <= constraints.maxHeight - screenPadding) {
                    element.size = Size(element.size.width, newHeight);
                  }
                  break;
                case Corner.none:
                  break;
              }
              
              _dragStartOffset = details.localPosition;
              _handleOverlaps(element); // Add this line
            });
          }
        },
        onPanEnd: (details) {
          setState(() {
            _isResizing = false;
            _resizingCorner = Corner.none;
          });
        },
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  void _checkAlignments(TextElement movingElement, Offset newPosition, BoxConstraints constraints) {
    Rect movingRect = Rect.fromLTWH(
      newPosition.dx, 
      newPosition.dy, 
      movingElement.size.width, 
      movingElement.size.height
    );
    
    for (var element in textElements) {
      if (element == movingElement) continue;
      
      Rect fixedRect = Rect.fromLTWH(
        element.position.dx,
        element.position.dy,
        element.size.width,
        element.size.height
      );
      
      _checkEdgeAlignment(movingRect, fixedRect);
      _checkCenterAlignment(movingRect, fixedRect);
      _checkSpacing(movingRect, fixedRect);
    }
    
    _checkScreenAlignment(movingRect, constraints);
  }

  void _checkEdgeAlignment(Rect moving, Rect fixed) {
    if ((moving.left - fixed.left).abs() < 20) {
      activeGuides.add(AlignmentGuide(GuideType.vertical, fixed.left, label: "Left"));
    }
    
    if ((moving.right - fixed.right).abs() < 20) {
      activeGuides.add(AlignmentGuide(GuideType.vertical, fixed.right, label: "Right"));
    }
    
    if ((moving.top - fixed.top).abs() < 20) {
      activeGuides.add(AlignmentGuide(GuideType.horizontal, fixed.top, label: "Top"));
    }
    
    if ((moving.bottom - fixed.bottom).abs() < 20) {
      activeGuides.add(AlignmentGuide(GuideType.horizontal, fixed.bottom, label: "Bottom"));
    }
  }

  void _checkCenterAlignment(Rect moving, Rect fixed) {
    if ((moving.center.dx - fixed.center.dx).abs() < 20) {
      activeGuides.add(AlignmentGuide(
        GuideType.vertical, 
        fixed.center.dx,
        label: "Center",
        color: Colors.green
      ));
    }
    
    if ((moving.center.dy - fixed.center.dy).abs() < 20) {
      activeGuides.add(AlignmentGuide(
        GuideType.horizontal, 
        fixed.center.dy,
        label: "Middle",
        color: Colors.green
      ));
    }
  }

  void _checkSpacing(Rect moving, Rect fixed) {
    if ((moving.left - fixed.right).abs() < 40) {
      activeGuides.add(AlignmentGuide(
        GuideType.vertical, 
        moving.left,
        label: "${(moving.left - fixed.right).abs().toStringAsFixed(0)}px",
        color: Colors.orange
      ));
    }
    
    if ((moving.top - fixed.bottom).abs() < 40) {
      activeGuides.add(AlignmentGuide(
        GuideType.horizontal, 
        moving.top,
        label: "${(moving.top - fixed.bottom).abs().toStringAsFixed(0)}px",
        color: Colors.orange
      ));
    }
  }

  void _checkScreenAlignment(Rect rect, BoxConstraints constraints) {
    if ((rect.left - screenPadding).abs() < 20) {
      activeGuides.add(AlignmentGuide(
        GuideType.vertical, 
        screenPadding,
        label: "Left Margin",
        color: Colors.purple
      ));
    }
    
    if ((rect.right - (constraints.maxWidth - screenPadding)).abs() < 20) {
      activeGuides.add(AlignmentGuide(
        GuideType.vertical, 
        constraints.maxWidth - screenPadding,
        label: "Right Margin",
        color: Colors.purple
      ));
    }
    
    if ((rect.top - screenPadding).abs() < 20) {
      activeGuides.add(AlignmentGuide(
        GuideType.horizontal, 
        screenPadding,
        label: "Top Margin",
        color: Colors.purple
      ));
    }
    
    if ((rect.bottom - (constraints.maxHeight - screenPadding)).abs() < 20) {
      activeGuides.add(AlignmentGuide(
        GuideType.horizontal, 
        constraints.maxHeight - screenPadding,
        label: "Bottom Margin",
        color: Colors.purple
      ));
    }
    
    final screenCenterX = constraints.maxWidth / 2;
    if ((rect.center.dx - screenCenterX).abs() < 20) {
      activeGuides.add(AlignmentGuide(
        GuideType.vertical, 
        screenCenterX,
        label: "Screen Center",
        color: Colors.purple
      ));
    }
    
    final screenCenterY = constraints.maxHeight / 2;
    if ((rect.center.dy - screenCenterY).abs() < 20) {
      activeGuides.add(AlignmentGuide(
        GuideType.horizontal, 
        screenCenterY,
        label: "Screen Middle",
        color: Colors.purple
      ));
    }
  }

  void _deleteSelectedElement() {
    if (_selectedElement != null) {
      setState(() {
        textElements.remove(_selectedElement);
        _selectedElement = null;
      });
    }
  }

  void _toggleEditMode() {
    // Save changes when leaving edit mode
    if (_editMode && _selectedElement != null) {
      _selectedElement!.saveCurrentState();
    }

    _cleanUpInvalidRectangles(); 
    setState(() {
      _editMode = !_editMode;
      _contentEditMode = false;
      _positionEditMode = false;
      activeGuides.clear();
      if (!_editMode) _selectedElement = null;
    });
  }
 
}

enum GuideType { horizontal, vertical, spacing }

class AlignmentGuide {
  final GuideType type;
  final double position;
  final String? label;
  final Color color;

  AlignmentGuide(this.type, this.position, {this.label, this.color = Colors.blue});
}

enum AlignmentType {
  left,
  right,
  top,
  bottom,
  centerVertical,
  centerHorizontal
}

class GridPainter extends CustomPainter {
  final double gridSize;
  final Color color;

  GridPainter({required this.gridSize, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DrawingPainter extends CustomPainter {
  final List<Rect> rectangles;
  final Rect? currentRect;
  final List<TextElement> textElements;
  final bool editMode;
  final TextElement? selectedElement;
  final List<DividerLine> dividerLines;
  final DividerLine? currentLine;
  final List<TableElement> tables;

  DrawingPainter({
    required this.rectangles,
    required this.currentRect,
    required this.textElements,
    required this.editMode,
    this.selectedElement,
    required this.dividerLines,
    this.currentLine,
    required this.tables
  });


  @override
  void paint(Canvas canvas, Size size) {
    Paint validPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = editMode ? 1.0 : 3.0;

    Paint invalidPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = editMode ? 1.0 : 3.0;

    for (var rect in rectangles) {
      // Draw invalid rectangles differently
      if (rect.width.abs() < _minRectangleWidth || 
          rect.height.abs() < _minRectangleHeight) {
        canvas.drawRect(rect, invalidPaint);
      } else {
        canvas.drawRect(rect, validPaint);
      }
    }

    if (currentRect != null) {
      // Draw current rectangle based on validity
      if (currentRect!.width.abs() < _minRectangleWidth || 
          currentRect!.height.abs() < _minRectangleHeight) {
        canvas.drawRect(currentRect!, invalidPaint);
      } else {
        canvas.drawRect(currentRect!, validPaint);
      }
    }

    if (editMode && textElements.isNotEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'Select text to edit',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(size.width / 2 - textPainter.width / 2, 20));
    }

    for (final line in dividerLines) {
      final linePaint = Paint()
        ..color = line.color
        ..strokeWidth = 2.0;
      
      if (line.isHorizontal) {
        canvas.drawLine(
          line.position,
          Offset(line.position.dx + line.length, line.position.dy),
          linePaint,
        );
      } else {
        canvas.drawLine(
          line.position,
          Offset(line.position.dx, line.position.dy + line.length),
          linePaint,
        );
      }

      
    }
     
    final linePaint = Paint()
        ..strokeWidth = 2.0;
    
    // Draw current line being drawn
    if (currentLine != null) {
        if (currentLine!.isHorizontal) {
          canvas.drawLine(  
            currentLine!.position,
            Offset(currentLine!.position.dx + currentLine!.length, currentLine!.position.dy),
            linePaint..color = Colors.blue,
          );
        } else {
          canvas.drawLine(
            currentLine!.position,
            Offset(currentLine!.position.dx, currentLine!.position.dy + currentLine!.length),
            linePaint..color = Colors.blue,
          );
        }
      }

    // Draw tables
    for (final table in tables) {
      final paint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      // Draw vertical lines
      for (final x in table.columnPositions) {
        canvas.drawLine(
          Offset(x, table.position.dy),
          Offset(x, table.position.dy + table.size.height),
          paint,
        );
      }

      // Draw horizontal lines
      for (final y in table.rowPositions) {
        canvas.drawLine(
          Offset(table.position.dx, y),
          Offset(table.position.dx + table.size.width, y),
          paint,
        );
      }
    }
    
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) => 
       oldDelegate.currentLine != currentLine ||
      oldDelegate.dividerLines != dividerLines ||
      oldDelegate.rectangles != rectangles ||
      oldDelegate.currentRect != currentRect ||
      oldDelegate.textElements != textElements ||
      oldDelegate.editMode != editMode ||
      oldDelegate.selectedElement != selectedElement ||
      oldDelegate.tables != tables;
}

class TextElement {
  Offset position;
  Size size;
  TextEditingController controller;
  TextAlign alignment;
  List<TextSpan> textSpans = [];
  bool showBullets = false;
  double fontSize;
  String fontFamily;

  TextElement({
    required this.position,
    required this.size,
    required this.controller,
    this.fontSize = 16,
    this.alignment = TextAlign.left,
    this.fontFamily = 'Arial'
  }) {
    _updateSpansFromText();
  }

  void saveCurrentState() {
    _updateSpansFromText();
  }

  void _updateSpansFromText() {
    final text = controller.text;
    if (text.isEmpty) {
      textSpans = [TextSpan(text: '', style: TextStyle(fontSize: fontSize, fontFamily: fontFamily))];
      return;
    }

    // If we have existing spans with styles, preserve them
    if (textSpans.isNotEmpty && textSpans.any((span) => span.style != null)) {
      List<TextSpan> newSpans = [];
      int currentPos = 0;
      
      for (final span in textSpans) {
        if (currentPos >= text.length) break;
        
        final spanText = span.text ?? '';
        final spanEnd = currentPos + spanText.length;
        final availableText = text.substring(
          currentPos, 
          min(spanEnd, text.length)
        );
        
        if (availableText.isNotEmpty) {
          newSpans.add(TextSpan(
            text: availableText,
            style: span.style?.copyWith(
              fontSize: span.style?.fontSize ?? fontSize,
              fontFamily: span.style?.fontFamily ?? fontFamily,
            ),
          ));
        }
        currentPos = spanEnd;
      }
      
      // Add any remaining text with default style
      if (currentPos < text.length) {
        newSpans.add(TextSpan(
          text: text.substring(currentPos),
          style: TextStyle(fontSize: fontSize, fontFamily: fontFamily),
        ));
      }
      
      textSpans = newSpans;
    } else {
      // No existing spans with style, create new ones
      textSpans = [TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, fontFamily: fontFamily),
      )];
    }
  }

  void changeFontFamily(String newFontFamily) {
    fontFamily = newFontFamily;
    _updateSpansFromText();
  }

  void applyFormatting(TextStyle style, {int start = 0, int? end}) {
    end ??= controller.text.length;
    if (start >= end) return;
    
    List<TextSpan> newSpans = [];
    int currentPos = 0;
    
    for (final span in textSpans) {
      if (currentPos >= end!) break;
      
      final spanText = span.text ?? '';
      final spanEnd = currentPos + spanText.length;
      
      if (spanEnd <= start) {
        newSpans.add(span);
        currentPos = spanEnd;
        continue;
      }
      
      // Split into before, selected, and after parts
      final beforeText = spanText.substring(0, max(0, start - currentPos));
      final selectedText = spanText.substring(
        max(0, start - currentPos),
        min(spanText.length, end - currentPos),
      );
      final afterText = spanText.substring(min(spanText.length, end - currentPos));
      
      if (beforeText.isNotEmpty) {
        newSpans.add(TextSpan(
          text: beforeText, 
          style: span.style ?? TextStyle(fontSize: fontSize, fontFamily: fontFamily)
        ));
      }
      
      if (selectedText.isNotEmpty) {
        newSpans.add(TextSpan(
          text: selectedText,
          style: (span.style ?? TextStyle(fontSize: fontSize, fontFamily: fontFamily)).merge(style),
        ));
      }
      
      if (afterText.isNotEmpty) {
        newSpans.add(TextSpan(
          text: afterText, 
          style: span.style ?? TextStyle(fontSize: fontSize, fontFamily: fontFamily)
        ));
      }
      
      currentPos = spanEnd;
      start = max(start, spanEnd);
      end = max(end, spanEnd);
    }
    
    textSpans = newSpans;
  }

  void toggleBullets() {
    final selection = controller.selection;
    if (!selection.isValid) {
      // No selection - apply to entire text
      final lines = controller.text.split('\n');
      final newText = lines.map((line) => line.startsWith('• ') ? line.substring(2) : '• $line').join('\n');
      controller.text = newText;
    } else {
      // Apply to selected lines
      final text = controller.text;
      final lines = text.split('\n');
      final startLine = text.substring(0, selection.start).split('\n').length - 1;
      final endLine = text.substring(0, selection.end).split('\n').length - 1;
      
      StringBuffer newText = StringBuffer();
      int offsetAdjustment = 0;
      
      for (int i = 0; i < lines.length; i++) {
        if (i >= startLine && i <= endLine) {
          if (lines[i].startsWith('• ')) {
            newText.write(lines[i].substring(2));
            if (i == startLine) offsetAdjustment -= 2;
          } else {
            newText.write('• ${lines[i]}');
            if (i == startLine) offsetAdjustment += 2;
          }
        } else {
          newText.write(lines[i]);
        }
        
        if (i < lines.length - 1) newText.write('\n');
      }
      
      controller.text = newText.toString();
      
      // Adjust selection
      controller.selection = selection.copyWith(
        baseOffset: max(0, selection.start + offsetAdjustment),
        extentOffset: max(0, selection.end + (endLine - startLine + 1) * offsetAdjustment),
      );
    }
    
    _updateSpansFromText();
  }

  void updateSizeBasedOnText() {
    final textPainter = TextPainter(
      text: TextSpan(
        text: controller.text,
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: size.width - 8); // Account for padding
    
    // Update size with padding (40px horizontal, 20px vertical)
    size = Size(
      (textPainter.width + 40).clamp(_minRectangleWidth, double.infinity),
      (textPainter.height + 20).clamp(_minRectangleHeight, double.infinity),
    );
  }

}

enum Corner { none, left, right, top, bottom }

class TextInputDialog extends StatefulWidget {
  const TextInputDialog({super.key});

  @override
  State<TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<TextInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add Text Content'),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: 'Type text...',
          enabled: true,
          border: OutlineInputBorder(),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey, width: 1.0),
            borderRadius: BorderRadius.circular(8.0),
          ),
        ),
        maxLines: null,
        keyboardType: TextInputType.multiline,
        autofocus: true,
      ),
      actions: [
        
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_controller.text.isNotEmpty) Navigator.pop(context, _controller.text);
          },
          child: Text('Add'),
        ),
      ],
    );
  }

  
}

class FormattingToolbar extends StatefulWidget {
  final TextElement element;
  final Function(TextElement) onFormatChanged;

  const FormattingToolbar({
    super.key,
    required this.element,
    required this.onFormatChanged,
  });

  @override
  State<FormattingToolbar> createState() => _FormattingToolbarState();
}

class _FormattingToolbarState extends State<FormattingToolbar> {
  bool _isBold = false;
  bool _isItalic = false;
  bool _hasSelection = false;
  final Color _textColor = Colors.black;

  @override
  void initState() {
    super.initState();
    widget.element.controller.addListener(_updateSelectionState);
    _updateSelectionState();
  }

  void _updateSelectionState() {
    final selection = widget.element.controller.selection;
    setState(() {
      _hasSelection = selection.start != selection.end;
    });
  }

  void _applyStyleToSelection(TextStyle style) {
    if (_hasSelection) {
      widget.element.applyFormatting(
        style,
        start: widget.element.controller.selection.start,
        end: widget.element.controller.selection.end,
      );
    } else {
      // Apply to all text if no selection
      widget.element.applyFormatting(style);
    }
    widget.onFormatChanged(widget.element);
  }

  void _changeAlignment(TextAlign alignment) {
    setState(() {
      widget.element.alignment = alignment;
    });
    widget.onFormatChanged(widget.element);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.element.position.dx,
      top: widget.element.position.dy + widget.element.size.height + 8,
      child: Column(
        children: [
          // Formatting Tools
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Wrap(
                spacing: 4,
                children: [
                  // Font family
                  IconButton(
                    icon: const Icon(Icons.font_download, size: 20),
                    onPressed: () => _showFontFamilyDialog(context),
                    tooltip: 'Font Family',
                  ),

                  // Font Size
                  IconButton(
                    icon: const Icon(Icons.text_fields, size: 20),
                    onPressed: () => _showFontSizeDialog(context),
                  ),
                  
                  // Bold
                  IconButton(
                    icon: const Icon(Icons.format_bold, size: 20),
                    color: _isBold ? Colors.blue : null,
                    onPressed: () {
                      _applyStyleToSelection(TextStyle(
                        fontWeight: _isBold ? FontWeight.normal : FontWeight.bold,
                      ));
                      setState(() => _isBold = !_isBold);
                    },
                  ),
                  
                  // Italic
                  IconButton(
                    icon: const Icon(Icons.format_italic, size: 20),
                    color: _isItalic ? Colors.blue : null,
                    onPressed: () {
                      _applyStyleToSelection(TextStyle(
                        fontStyle: _isItalic ? FontStyle.normal : FontStyle.italic,
                      ));
                      setState(() => _isItalic = !_isItalic);
                    },
                  ),
                  
                  // Color
                  IconButton(
                    icon: const Icon(Icons.color_lens, size: 20),
                    onPressed: () => _showColorPicker(context),
                  ),
                  
                  // Bullets
                  IconButton(
                    icon: const Icon(Icons.format_list_bulleted, size: 20),
                    onPressed: () {
                      widget.element.toggleBullets();
                      widget.onFormatChanged(widget.element);
                    },
                  ),

                  DropdownButton<TextAlign>(
                    value: widget.element.alignment,
                    items: [
                      DropdownMenuItem(
                        value: TextAlign.left,
                        child: Row(children: [Icon(Icons.format_align_left), Text(' Left')]),
                      ),
                      DropdownMenuItem(
                        value: TextAlign.center,
                        child: Row(children: [Icon(Icons.format_align_center), Text(' Center')]),
                      ),
                      DropdownMenuItem(
                        value: TextAlign.right,
                        child: Row(children: [Icon(Icons.format_align_right), Text(' Right')]),
                      ),
                      DropdownMenuItem(
                        value: TextAlign.justify,
                        child: Row(children: [Icon(Icons.format_align_justify), Text(' Justify')]),
                      ),
                    ],
                    onChanged: (alignment) {
                      if (alignment != null) {
                        _changeAlignment(alignment);
                      }
                    },
                  ),
                  
                ],
              ),
            ),
          ),
          
          // Directional Controls
          _buildDirectionalControls(),
        ],
      ),
    );
  }

  void _spaceElementsEvenlyFromToolbar() {
    final parentState = context.findAncestorStateOfType<_DrawingScreenState>();
    parentState?._spaceElementsEvenly();
  }

  

  Widget _buildDirectionalControls() {
    const double moveAmount = 5.0;
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.arrow_upward, size: 20),
              onPressed: () => _moveElement(0, -moveAmount),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, size: 20),
                  onPressed: () => _moveElement(-moveAmount, 0),
                ),
                SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.arrow_forward, size: 20),
                  onPressed: () => _moveElement(moveAmount, 0),
                ),
              ],
            ),
            IconButton(
              icon: Icon(Icons.arrow_downward, size: 20),
              onPressed: () => _moveElement(0, moveAmount),
            ),
          ],
        ),
      ),
    );
  }

  void _moveElement(double dx, double dy) { 
    final double screenPadding = 20.0;
    final constraints = BoxConstraints(
      maxWidth: MediaQuery.of(context).size.width - screenPadding * 2,
      maxHeight: MediaQuery.of(context).size.height - screenPadding * 2,
    );
    
    setState(() {
      widget.element.position = Offset(
        (widget.element.position.dx + dx).clamp(
          screenPadding, 
          constraints.maxWidth - widget.element.size.width - screenPadding
        ),
        (widget.element.position.dy + dy).clamp(
          screenPadding,
          constraints.maxHeight - widget.element.size.height - screenPadding
        ),
      );
    });
    widget.onFormatChanged(widget.element);
  }

  void _showFontSizeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Font Size'),
          content: DropdownButton<double>(
            value: widget.element.fontSize,
            items: [12, 14, 16, 18, 20, 24, 28].map((size) {
              return DropdownMenuItem(
                value: size.toDouble(),
                child: Text('$size'),
              );
            }).toList(),
            onChanged: (size) {
              if (size != null) {
                _applyStyleToSelection(TextStyle(fontSize: size));
                widget.onFormatChanged(widget.element..fontSize = size);
                Navigator.pop(context);
              }
            },
          ),
        );
      },
    );
  }

  void _showFontFamilyDialog(BuildContext context) {
    final List<String> fontFamilies = [
      'Arial',
      'Times New Roman',
      'Courier New',
      'Georgia',
      'Palatino',
    ];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Font Family'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: fontFamilies.length,
              itemBuilder: (context, index) {
                final family = fontFamilies[index];
                return ListTile(
                  title: Text(
                    family,
                    style: TextStyle(fontFamily: family),
                  ),
                  onTap: () {
                    widget.element.changeFontFamily(family);
                    widget.onFormatChanged(widget.element);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showColorPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Text Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _textColor,
            onColorChanged: (color) {
              _applyStyleToSelection(TextStyle(color: color));
            },
          ),
        ),
        actions: [
          TextButton(
            child: Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

class TableElement {
  final List<double> columnPositions;
  final List<double> rowPositions;
  final List<List<String>> cells;
  final Offset position;
  final Size size;

  TableElement({
    required this.columnPositions,
    required this.rowPositions,
    required this.cells,
    required this.position,
    required this.size,
  });

  int get columnCount => columnPositions.length - 1;
  int get rowCount => rowPositions.length - 1;
}

