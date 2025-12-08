# GenUI with Remote Flutter Widgets (RFW)

## Table of Contents

1. [Overview](#overview)
2. [Critical Understanding: RFW is NOT Dart](#critical-understanding-rfw-is-not-dart)
3. [Architecture](#architecture)
4. [The genui_render Tool](#the-genui_render-tool)
5. [RFW Syntax Rules](#rfw-syntax-rules)
6. [Complete Syntax Reference](#complete-syntax-reference)
7. [Strengths and Weaknesses](#strengths-and-weaknesses)
8. [Examples](#examples)
   - [Example 1: Simple Greeting Card](#example-1-simple-greeting-card-beginner)
   - [Example 2: Location Display Card](#example-2-location-display-card-intermediate)
   - [Example 3: Interactive Form](#example-3-interactive-form-advanced)
9. [System Prompt Template](#system-prompt-template-for-ai-agents)
10. [Troubleshooting](#troubleshooting)
11. [Color Reference](#color-reference)

---

## Overview

**GenUI** (Generative UI) allows an AI agent to dynamically create and render user interface widgets within a chat conversation. This is achieved using **Remote Flutter Widgets (RFW)**, a Flutter package that enables secure, sandboxed rendering of UI definitions sent from a server.

### What This Enables

- AI agent can show interactive UI elements (buttons, forms, cards)
- User interactions are captured and can be sent back to the agent
- UI updates without app store releases
- Secure - no arbitrary code execution

### Key Components

| Component | Role |
|-----------|------|
| `genui_render` tool | Client-side tool the agent calls to render UI |
| RFW Library Text | Text format defining the widget structure |
| DynamicContent | Data binding for dynamic values |
| Event System | Captures user interactions (button clicks, etc.) |

---

## Critical Understanding: RFW is NOT Dart

> **⚠️ THIS IS THE MOST IMPORTANT SECTION**

RFW uses a **Dart-like DSL (Domain Specific Language)**, but it is **NOT** Dart code. This distinction is the #1 source of errors when AI agents generate RFW.

### Side-by-Side Comparison

```
╔═══════════════════════════════════════════════════════════════════╗
║                        DART (Flutter)                             ║
╠═══════════════════════════════════════════════════════════════════╣
║ Container(                                                        ║
║   padding: EdgeInsets.all(16.0),              // ❌ Class method  ║
║   color: Colors.blue,                         // ❌ Static const  ║
║   child: Column(                                                  ║
║     mainAxisSize: MainAxisSize.min,           // ❌ Enum value    ║
║     crossAxisAlignment: CrossAxisAlignment.start,                 ║
║     children: [                                                   ║
║       Text('Hello',                           // ❌ Positional    ║
║         style: TextStyle(                     // ❌ Constructor   ║
║           fontWeight: FontWeight.bold,        // ❌ Enum value    ║
║         ),                                                        ║
║       ),                                                          ║
║     ],                                                            ║
║   ),                                                              ║
║ )                                                                 ║
╚═══════════════════════════════════════════════════════════════════╝

╔═══════════════════════════════════════════════════════════════════╗
║                   RFW (Remote Flutter Widgets)                    ║
╠═══════════════════════════════════════════════════════════════════╣
║ Container(                                                        ║
║   padding: [16.0, 16.0, 16.0, 16.0],          // ✅ Array [LTRB]  ║
║   color: 0xFF2196F3,                          // ✅ Hex integer   ║
║   child: Column(                                                  ║
║     mainAxisSize: "min",                      // ✅ String        ║
║     crossAxisAlignment: "start",              // ✅ String        ║
║     children: [                                                   ║
║       Text(                                                       ║
║         text: "Hello",                        // ✅ Named param   ║
║         style: {                              // ✅ Map literal   ║
║           fontWeight: "bold",                 // ✅ String        ║
║         },                                                        ║
║       ),                                                          ║
║     ],                                                            ║
║   ),                                                              ║
║ )                                                                 ║
╚═══════════════════════════════════════════════════════════════════╝
```

### Key Differences Summary

| Concept | Dart (Flutter) | RFW |
|---------|---------------|-----|
| Enums | `MainAxisSize.min` | `"min"` |
| Padding | `EdgeInsets.all(16.0)` | `[16.0, 16.0, 16.0, 16.0]` |
| Colors | `Colors.blue` | `0xFF2196F3` |
| Text style | `TextStyle(...)` | `{ fontSize: 16.0 }` |
| Text content | `Text('Hello')` | `Text(text: "Hello")` |
| Font weight | `FontWeight.bold` | `"bold"` |
| Alignment | `CrossAxisAlignment.start` | `"start"` |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           AI AGENT                                  │
│                                                                     │
│  User: "Show my location"                                          │
│  Agent: 1. Calls get_my_location tool → gets coordinates           │
│         2. Calls genui_render tool with LocationCard widget        │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                │ SSE Stream: TOOL_CALL_START
                                │             TOOL_CALL_ARGS (JSON)
                                │             TOOL_CALL_END
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        FLUTTER CLIENT                               │
│                                                                     │
│  1. Receives TOOL_CALL events for "genui_render"                   │
│  2. Extracts: widget_name, library_text, data                      │
│  3. Parses library_text using RFW parser                           │
│  4. Creates DynamicContent with data values                        │
│  5. Renders RemoteWidget in chat message                           │
│  6. User clicks button → event fires → (future: send to agent)     │
│                                                                     │
│  NOTE: No result is sent back for genui_render (UI only)           │
└─────────────────────────────────────────────────────────────────────┘
```

### Tool Flow Comparison

| Tool | Client Executes | Result Sent to Server |
|------|-----------------|----------------------|
| `get_my_location` | ✅ Yes (GPS) | ✅ Yes (coordinates) |
| `genui_render` | ✅ Yes (render) | ❌ No (UI only) |

---

## The genui_render Tool

### Tool Schema

```json
{
  "name": "genui_render",
  "description": "Render a dynamic UI widget in the chat. Use this to display interactive elements like buttons, forms, data cards, or any visual content.",
  "parameters": {
    "type": "object",
    "properties": {
      "widget_name": {
        "type": "string",
        "description": "Name of the widget to render. Must exactly match a widget defined in library_text."
      },
      "library_text": {
        "type": "string",
        "description": "RFW library text defining the widget. Must start with imports and contain a widget definition."
      },
      "library_name": {
        "type": "string",
        "description": "Namespace for the library. Default: 'agent'",
        "default": "agent"
      },
      "data": {
        "type": "object",
        "description": "Dynamic data accessible in the widget via data.fieldName syntax.",
        "default": {}
      }
    },
    "required": ["widget_name", "library_text"]
  }
}
```

### Tool Call Example

```json
{
  "widget_name": "GreetingCard",
  "library_text": "import core.widgets;\nimport material;\n\nwidget GreetingCard = Card(\n  child: Padding(\n    padding: [16.0, 16.0, 16.0, 16.0],\n    child: Text(text: data.message),\n  ),\n);",
  "data": {
    "message": "Hello, World!"
  }
}
```

---

## RFW Syntax Rules

### Rule 1: Always Include Imports

Every RFW library MUST start with imports:

```
import core.widgets;
import material;

widget MyWidget = ...
```

Without imports, widgets like `Container`, `Card`, `ElevatedButton` won't be recognized.

### Rule 2: Widget Definition Syntax

```
widget WidgetName = WidgetType(
  property: value,
  child: ChildWidget(...),
);
```

- `widget` keyword (lowercase)
- Widget name (PascalCase)
- `=` assignment
- Widget constructor
- Semicolon at the end

### Rule 3: Enums Are Strings

```
// ❌ WRONG - Dart enum syntax
mainAxisSize: MainAxisSize.min
crossAxisAlignment: CrossAxisAlignment.start
fontWeight: FontWeight.bold
textAlign: TextAlign.center

// ✅ CORRECT - RFW string syntax
mainAxisSize: "min"
crossAxisAlignment: "start"
fontWeight: "bold"
textAlign: "center"
```

**Valid String Values:**

| Property | Valid Values |
|----------|--------------|
| `mainAxisSize` | `"min"`, `"max"` |
| `mainAxisAlignment` | `"start"`, `"center"`, `"end"`, `"spaceBetween"`, `"spaceAround"`, `"spaceEvenly"` |
| `crossAxisAlignment` | `"start"`, `"center"`, `"end"`, `"stretch"`, `"baseline"` |
| `fontWeight` | `"normal"`, `"bold"`, `"w100"` through `"w900"` |
| `fontStyle` | `"normal"`, `"italic"` |
| `textAlign` | `"left"`, `"center"`, `"right"`, `"justify"`, `"start"`, `"end"` |
| `overflow` | `"clip"`, `"fade"`, `"ellipsis"`, `"visible"` |

### Rule 4: Padding/Margin Arrays

```
// ❌ WRONG - Dart EdgeInsets
padding: EdgeInsets.all(16.0)
padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0)
padding: EdgeInsets.only(left: 8.0, top: 16.0)

// ✅ CORRECT - RFW arrays [left, top, right, bottom]
padding: [16.0, 16.0, 16.0, 16.0]    // all sides 16
padding: [16.0, 8.0, 16.0, 8.0]      // horizontal 16, vertical 8
padding: [8.0, 16.0, 0.0, 0.0]       // left 8, top 16, right 0, bottom 0
```

### Rule 5: Colors Are Hex Integers

```
// ❌ WRONG - Dart color classes
color: Colors.blue
color: Colors.red.shade500
color: Color(0xFF2196F3)

// ✅ CORRECT - RFW hex integers
color: 0xFF2196F3    // Blue
color: 0xFFE53935    // Red
color: 0xFF4CAF50    // Green
```

Format: `0xAARRGGBB`
- `AA` = Alpha (opacity): `FF` = 100%, `80` = 50%, `00` = 0%
- `RR` = Red: `00` to `FF`
- `GG` = Green: `00` to `FF`
- `BB` = Blue: `00` to `FF`

### Rule 6: Text Widget Requires Named Parameter

```
// ❌ WRONG - Positional parameter
Text("Hello World")

// ✅ CORRECT - Named parameter
Text(text: "Hello World")
```

### Rule 7: TextStyle Is a Map

```
// ❌ WRONG - Dart TextStyle constructor
style: TextStyle(
  fontSize: 16.0,
  fontWeight: FontWeight.bold,
  color: Colors.black,
)

// ✅ CORRECT - RFW map syntax
style: {
  fontSize: 16.0,
  fontWeight: "bold",
  color: 0xFF000000,
}
```

### Rule 8: Event Syntax

```
// ✅ CORRECT event syntax
onPressed: event "event_name" {}
onPressed: event "button_clicked" { "id": "123" }
onChanged: event "value_changed" { "field": "email" }

// Event with dynamic data
onPressed: event "select_item" { "item_id": data.id }
```

### Rule 9: Dynamic Data Access

Data passed in the `data` parameter is accessed via `data.fieldName`:

```json
// Tool call data parameter:
{
  "data": {
    "userName": "John",
    "userAge": 30,
    "isActive": true
  }
}
```

```
// In RFW:
Text(text: data.userName)     // "John"
Text(text: data.userAge)      // "30" (rendered as text)
```

### Rule 10: BoxDecoration Syntax

```
// ✅ CORRECT
Container(
  decoration: {
    color: 0xFFE3F2FD,
    borderRadius: [12.0, 12.0, 12.0, 12.0],
    border: {
      color: 0xFF2196F3,
      width: 2.0,
    },
  },
  child: ...
)
```

---

## Complete Syntax Reference

### Layout Widgets

```
// Container
Container(
  width: 200.0,
  height: 100.0,
  padding: [16.0, 16.0, 16.0, 16.0],
  margin: [8.0, 8.0, 8.0, 8.0],
  decoration: {
    color: 0xFFFFFFFF,
    borderRadius: [8.0, 8.0, 8.0, 8.0],
  },
  child: ...
)

// Column (vertical layout)
Column(
  mainAxisSize: "min",
  mainAxisAlignment: "start",
  crossAxisAlignment: "center",
  children: [
    Widget1(),
    Widget2(),
    Widget3(),
  ],
)

// Row (horizontal layout)
Row(
  mainAxisAlignment: "spaceBetween",
  crossAxisAlignment: "center",
  children: [
    Widget1(),
    Widget2(),
  ],
)

// SizedBox (spacing)
SizedBox(height: 16.0)
SizedBox(width: 8.0)
SizedBox(width: 100.0, height: 50.0)

// Padding
Padding(
  padding: [16.0, 8.0, 16.0, 8.0],
  child: ...
)

// Center
Center(
  child: ...
)

// Expanded (in Row/Column)
Row(
  children: [
    Expanded(child: Text(text: "Takes remaining space")),
    Text(text: "Fixed"),
  ],
)
```

### Text and Styling

```
// Basic text
Text(text: "Hello World")

// Styled text
Text(
  text: "Styled Text",
  style: {
    fontSize: 24.0,
    fontWeight: "bold",
    fontStyle: "italic",
    color: 0xFF2196F3,
    letterSpacing: 1.5,
    height: 1.5,
  },
  textAlign: "center",
  maxLines: 2,
  overflow: "ellipsis",
)
```

### Buttons

```
// Elevated Button (filled)
ElevatedButton(
  onPressed: event "submit" {},
  child: Text(text: "Submit"),
)

// Text Button (flat)
TextButton(
  onPressed: event "cancel" {},
  child: Text(text: "Cancel"),
)

// Outlined Button
OutlinedButton(
  onPressed: event "details" {},
  child: Text(text: "View Details"),
)

// Icon Button
IconButton(
  icon: Icon(icon: 0xe5d2, size: 24.0),
  onPressed: event "menu" {},
)
```

### Cards and Containers

```
// Card
Card(
  elevation: 4.0,
  child: Padding(
    padding: [16.0, 16.0, 16.0, 16.0],
    child: ...
  ),
)

// Decorated Container
Container(
  decoration: {
    color: 0xFFE8F5E9,
    borderRadius: [12.0, 12.0, 12.0, 12.0],
    border: {
      color: 0xFF4CAF50,
      width: 1.0,
    },
    boxShadow: [
      {
        color: 0x40000000,
        blurRadius: 4.0,
        offset: [0.0, 2.0],
      },
    ],
  },
  child: ...
)
```

### Form Elements

```
// TextField
TextField(
  decoration: {
    labelText: "Email",
    hintText: "Enter your email",
    border: "outline",
    prefixIcon: Icon(icon: 0xe0be),
  },
  keyboardType: "emailAddress",
  onChanged: event "email_changed" {},
)

// Checkbox
Checkbox(
  value: data.isChecked,
  onChanged: event "checkbox_toggled" {},
)

// Switch
Switch(
  value: data.isEnabled,
  onChanged: event "switch_toggled" {},
)

// Slider
Slider(
  value: data.sliderValue,
  min: 0.0,
  max: 100.0,
  onChanged: event "slider_changed" {},
)
```

### Icons

```
// Material icon by code point
Icon(
  icon: 0xe87c,      // favorite icon
  size: 24.0,
  color: 0xFFE91E63,
)

// Common icon codes:
// 0xe87c = favorite (heart)
// 0xe8b6 = home
// 0xe5d2 = menu
// 0xe5cd = close
// 0xe145 = add
// 0xe15b = delete
// 0xe3c9 = location_on
// 0xe0be = email
// 0xe7fd = person
// 0xe8b8 = settings
```

---

## Strengths and Weaknesses

### Strengths

| Strength | Description |
|----------|-------------|
| **Security** | Sandboxed execution - cannot run arbitrary code, access filesystem, or make network requests |
| **Portability** | Same widget definition renders identically on iOS, Android, macOS, Windows, Linux, Web |
| **Hot Updates** | UI can be changed server-side without app store review or updates |
| **Lightweight** | Text format is human-readable and debuggable; binary format is compact for production |
| **Type Safety** | Parse-time validation catches syntax errors before rendering |
| **Event System** | Built-in `event` keyword for capturing user interactions |
| **Data Binding** | `DynamicContent` enables reactive updates when data changes |
| **Flutter Native** | Renders actual Flutter widgets, not a webview - full performance |

### Weaknesses

| Weakness | Impact | Mitigation |
|----------|--------|------------|
| **Not Dart** | AI agents generate invalid Dart-style syntax | Explicit rules in system prompt with examples |
| **Limited Widgets** | Only pre-registered widgets are available | Document available widgets; add custom LocalWidgets |
| **No Conditionals** | Cannot use `if`/`else` in widget tree | Pre-compute variants in data; use visibility patterns |
| **No Loops** | Only `...for item in list:` spread syntax | Structure data as arrays before sending |
| **No Functions** | Cannot define helper methods | Keep widgets simple; compose from smaller parts |
| **String Enums** | Different from Dart enum syntax | Provide reference table in prompt |
| **Array Padding** | Unintuitive `[L,T,R,B]` vs EdgeInsets | Clear examples in prompt |
| **Hex Colors** | Must know or look up color codes | Provide color reference table |
| **Cryptic Errors** | Parser errors don't always pinpoint issue | Test incrementally; validate before sending |
| **No State** | Widgets are stateless; state lives in data | Server manages state; send updates via new renders |

### What RFW Cannot Do

- Execute arbitrary Dart code
- Make HTTP requests
- Access device filesystem
- Use platform channels
- Create custom painters/animations (limited support)
- Use widgets not registered in Runtime

---

## Examples

### Example 1: Simple Greeting Card (Beginner)

**Use Case:** Display a simple card with a message and a button.

**Complexity:** Low - Basic layout, text, button, event

#### Tool Call

```json
{
  "widget_name": "GreetingCard",
  "library_text": "import core.widgets;\nimport material;\n\nwidget GreetingCard = Card(\n  child: Padding(\n    padding: [20.0, 20.0, 20.0, 20.0],\n    child: Column(\n      mainAxisSize: \"min\",\n      children: [\n        Text(\n          text: data.greeting,\n          style: {\n            fontSize: 24.0,\n            fontWeight: \"bold\",\n            color: 0xFF1976D2,\n          },\n        ),\n        SizedBox(height: 12.0),\n        Text(\n          text: data.message,\n          style: {\n            fontSize: 16.0,\n            color: 0xFF616161,\n          },\n        ),\n        SizedBox(height: 20.0),\n        ElevatedButton(\n          onPressed: event \"acknowledge\" {},\n          child: Text(text: \"Got it!\"),\n        ),\n      ],\n    ),\n  ),\n);",
  "data": {
    "greeting": "Welcome!",
    "message": "Thanks for using our app. Click below to continue."
  }
}
```

#### Formatted Library Text

```
import core.widgets;
import material;

widget GreetingCard = Card(
  child: Padding(
    padding: [20.0, 20.0, 20.0, 20.0],
    child: Column(
      mainAxisSize: "min",
      children: [
        Text(
          text: data.greeting,
          style: {
            fontSize: 24.0,
            fontWeight: "bold",
            color: 0xFF1976D2,
          },
        ),
        SizedBox(height: 12.0),
        Text(
          text: data.message,
          style: {
            fontSize: 16.0,
            color: 0xFF616161,
          },
        ),
        SizedBox(height: 20.0),
        ElevatedButton(
          onPressed: event "acknowledge" {},
          child: Text(text: "Got it!"),
        ),
      ],
    ),
  ),
);
```

#### Concepts Demonstrated

1. **Imports** - Required `core.widgets` and `material`
2. **Card** - Material card container
3. **Padding** - Array format `[20.0, 20.0, 20.0, 20.0]`
4. **Column** - Vertical layout with `mainAxisSize: "min"`
5. **Text styling** - Map syntax with string fontWeight
6. **Dynamic data** - `data.greeting` and `data.message`
7. **Button event** - `event "acknowledge" {}`

---

### Example 2: Location Display Card (Intermediate)

**Use Case:** Display GPS coordinates with formatted data and multiple action buttons.

**Complexity:** Medium - Multiple data fields, nested layouts, multiple events, styling

#### Tool Call

```json
{
  "widget_name": "LocationCard",
  "library_text": "import core.widgets;\nimport material;\n\nwidget LocationCard = Card(\n  child: Padding(\n    padding: [16.0, 16.0, 16.0, 16.0],\n    child: Column(\n      mainAxisSize: \"min\",\n      crossAxisAlignment: \"start\",\n      children: [\n        Row(\n          children: [\n            Icon(icon: 0xe55f, size: 28.0, color: 0xFFE53935),\n            SizedBox(width: 12.0),\n            Text(\n              text: \"Your Location\",\n              style: { fontSize: 20.0, fontWeight: \"bold\" },\n            ),\n          ],\n        ),\n        SizedBox(height: 16.0),\n        Container(\n          padding: [12.0, 12.0, 12.0, 12.0],\n          decoration: {\n            color: 0xFFF5F5F5,\n            borderRadius: [8.0, 8.0, 8.0, 8.0],\n          },\n          child: Column(\n            crossAxisAlignment: \"start\",\n            children: [\n              Row(\n                mainAxisAlignment: \"spaceBetween\",\n                children: [\n                  Column(\n                    crossAxisAlignment: \"start\",\n                    children: [\n                      Text(text: \"Latitude\", style: { fontSize: 12.0, color: 0xFF9E9E9E }),\n                      Text(text: data.latitude, style: { fontSize: 18.0, fontWeight: \"w500\" }),\n                    ],\n                  ),\n                  Column(\n                    crossAxisAlignment: \"start\",\n                    children: [\n                      Text(text: \"Longitude\", style: { fontSize: 12.0, color: 0xFF9E9E9E }),\n                      Text(text: data.longitude, style: { fontSize: 18.0, fontWeight: \"w500\" }),\n                    ],\n                  ),\n                ],\n              ),\n              SizedBox(height: 12.0),\n              Row(\n                mainAxisAlignment: \"spaceBetween\",\n                children: [\n                  Column(\n                    crossAxisAlignment: \"start\",\n                    children: [\n                      Text(text: \"Accuracy\", style: { fontSize: 12.0, color: 0xFF9E9E9E }),\n                      Text(text: data.accuracy, style: { fontSize: 14.0 }),\n                    ],\n                  ),\n                  Column(\n                    crossAxisAlignment: \"start\",\n                    children: [\n                      Text(text: \"Altitude\", style: { fontSize: 12.0, color: 0xFF9E9E9E }),\n                      Text(text: data.altitude, style: { fontSize: 14.0 }),\n                    ],\n                  ),\n                ],\n              ),\n            ],\n          ),\n        ),\n        SizedBox(height: 16.0),\n        Row(\n          mainAxisAlignment: \"end\",\n          children: [\n            TextButton(\n              onPressed: event \"copy_location\" { \"lat\": data.latitude, \"lng\": data.longitude },\n              child: Text(text: \"Copy\"),\n            ),\n            SizedBox(width: 8.0),\n            ElevatedButton(\n              onPressed: event \"refresh_location\" {},\n              child: Text(text: \"Refresh\"),\n            ),\n          ],\n        ),\n      ],\n    ),\n  ),\n);",
  "data": {
    "latitude": "29.7364",
    "longitude": "-95.4089",
    "accuracy": "±10m",
    "altitude": "15m"
  }
}
```

#### Formatted Library Text

```
import core.widgets;
import material;

widget LocationCard = Card(
  child: Padding(
    padding: [16.0, 16.0, 16.0, 16.0],
    child: Column(
      mainAxisSize: "min",
      crossAxisAlignment: "start",
      children: [
        // Header with icon
        Row(
          children: [
            Icon(icon: 0xe55f, size: 28.0, color: 0xFFE53935),
            SizedBox(width: 12.0),
            Text(
              text: "Your Location",
              style: { fontSize: 20.0, fontWeight: "bold" },
            ),
          ],
        ),
        SizedBox(height: 16.0),

        // Data container with background
        Container(
          padding: [12.0, 12.0, 12.0, 12.0],
          decoration: {
            color: 0xFFF5F5F5,
            borderRadius: [8.0, 8.0, 8.0, 8.0],
          },
          child: Column(
            crossAxisAlignment: "start",
            children: [
              // Lat/Lng row
              Row(
                mainAxisAlignment: "spaceBetween",
                children: [
                  Column(
                    crossAxisAlignment: "start",
                    children: [
                      Text(text: "Latitude", style: { fontSize: 12.0, color: 0xFF9E9E9E }),
                      Text(text: data.latitude, style: { fontSize: 18.0, fontWeight: "w500" }),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: "start",
                    children: [
                      Text(text: "Longitude", style: { fontSize: 12.0, color: 0xFF9E9E9E }),
                      Text(text: data.longitude, style: { fontSize: 18.0, fontWeight: "w500" }),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 12.0),
              // Accuracy/Altitude row
              Row(
                mainAxisAlignment: "spaceBetween",
                children: [
                  Column(
                    crossAxisAlignment: "start",
                    children: [
                      Text(text: "Accuracy", style: { fontSize: 12.0, color: 0xFF9E9E9E }),
                      Text(text: data.accuracy, style: { fontSize: 14.0 }),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: "start",
                    children: [
                      Text(text: "Altitude", style: { fontSize: 12.0, color: 0xFF9E9E9E }),
                      Text(text: data.altitude, style: { fontSize: 14.0 }),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 16.0),

        // Action buttons
        Row(
          mainAxisAlignment: "end",
          children: [
            TextButton(
              onPressed: event "copy_location" { "lat": data.latitude, "lng": data.longitude },
              child: Text(text: "Copy"),
            ),
            SizedBox(width: 8.0),
            ElevatedButton(
              onPressed: event "refresh_location" {},
              child: Text(text: "Refresh"),
            ),
          ],
        ),
      ],
    ),
  ),
);
```

#### Concepts Demonstrated

1. **Icon** - Material icon with hex code `0xe55f` (location_on)
2. **Nested layouts** - Column > Row > Column pattern
3. **BoxDecoration** - Background color and border radius
4. **Multiple data fields** - latitude, longitude, accuracy, altitude
5. **Events with data** - `event "copy_location" { "lat": data.latitude, ... }`
6. **Font weights** - Using `"w500"` for medium weight
7. **Color hierarchy** - Grey labels, dark values

---

### Example 3: Interactive Form (Advanced)

**Use Case:** Contact form with multiple input fields, checkbox for terms, and submit/cancel actions.

**Complexity:** High - Form fields, checkbox, multiple events, full layout

#### Tool Call

```json
{
  "widget_name": "ContactForm",
  "library_text": "import core.widgets;\nimport material;\n\nwidget ContactForm = Card(\n  child: Padding(\n    padding: [20.0, 20.0, 20.0, 20.0],\n    child: Column(\n      mainAxisSize: \"min\",\n      crossAxisAlignment: \"stretch\",\n      children: [\n        Text(\n          text: \"Contact Us\",\n          style: { fontSize: 24.0, fontWeight: \"bold\", color: 0xFF1976D2 },\n        ),\n        SizedBox(height: 8.0),\n        Text(\n          text: \"We'd love to hear from you. Fill out the form below.\",\n          style: { fontSize: 14.0, color: 0xFF757575 },\n        ),\n        SizedBox(height: 24.0),\n        TextField(\n          decoration: {\n            labelText: \"Name\",\n            hintText: \"Enter your full name\",\n            border: \"outline\",\n            prefixIcon: Icon(icon: 0xe7fd),\n          },\n          onChanged: event \"field_changed\" { \"field\": \"name\" },\n        ),\n        SizedBox(height: 16.0),\n        TextField(\n          decoration: {\n            labelText: \"Email\",\n            hintText: \"your.email@example.com\",\n            border: \"outline\",\n            prefixIcon: Icon(icon: 0xe0be),\n          },\n          keyboardType: \"emailAddress\",\n          onChanged: event \"field_changed\" { \"field\": \"email\" },\n        ),\n        SizedBox(height: 16.0),\n        TextField(\n          decoration: {\n            labelText: \"Subject\",\n            hintText: \"What is this about?\",\n            border: \"outline\",\n          },\n          onChanged: event \"field_changed\" { \"field\": \"subject\" },\n        ),\n        SizedBox(height: 16.0),\n        TextField(\n          decoration: {\n            labelText: \"Message\",\n            hintText: \"Tell us more...\",\n            border: \"outline\",\n            alignLabelWithHint: true,\n          },\n          maxLines: 5,\n          onChanged: event \"field_changed\" { \"field\": \"message\" },\n        ),\n        SizedBox(height: 16.0),\n        Row(\n          children: [\n            Checkbox(\n              value: data.agreedToTerms,\n              onChanged: event \"terms_toggled\" {},\n            ),\n            SizedBox(width: 8.0),\n            Expanded(\n              child: Text(\n                text: \"I agree to the Terms of Service and Privacy Policy\",\n                style: { fontSize: 14.0, color: 0xFF616161 },\n              ),\n            ),\n          ],\n        ),\n        SizedBox(height: 24.0),\n        Row(\n          mainAxisAlignment: \"end\",\n          children: [\n            TextButton(\n              onPressed: event \"form_cancel\" {},\n              child: Text(text: \"Cancel\"),\n            ),\n            SizedBox(width: 12.0),\n            ElevatedButton(\n              onPressed: event \"form_submit\" {},\n              child: Padding(\n                padding: [16.0, 0.0, 16.0, 0.0],\n                child: Text(text: \"Send Message\"),\n              ),\n            ),\n          ],\n        ),\n      ],\n    ),\n  ),\n);",
  "data": {
    "agreedToTerms": false
  }
}
```

#### Formatted Library Text

```
import core.widgets;
import material;

widget ContactForm = Card(
  child: Padding(
    padding: [20.0, 20.0, 20.0, 20.0],
    child: Column(
      mainAxisSize: "min",
      crossAxisAlignment: "stretch",
      children: [
        // Header
        Text(
          text: "Contact Us",
          style: { fontSize: 24.0, fontWeight: "bold", color: 0xFF1976D2 },
        ),
        SizedBox(height: 8.0),
        Text(
          text: "We'd love to hear from you. Fill out the form below.",
          style: { fontSize: 14.0, color: 0xFF757575 },
        ),
        SizedBox(height: 24.0),

        // Name field
        TextField(
          decoration: {
            labelText: "Name",
            hintText: "Enter your full name",
            border: "outline",
            prefixIcon: Icon(icon: 0xe7fd),
          },
          onChanged: event "field_changed" { "field": "name" },
        ),
        SizedBox(height: 16.0),

        // Email field
        TextField(
          decoration: {
            labelText: "Email",
            hintText: "your.email@example.com",
            border: "outline",
            prefixIcon: Icon(icon: 0xe0be),
          },
          keyboardType: "emailAddress",
          onChanged: event "field_changed" { "field": "email" },
        ),
        SizedBox(height: 16.0),

        // Subject field
        TextField(
          decoration: {
            labelText: "Subject",
            hintText: "What is this about?",
            border: "outline",
          },
          onChanged: event "field_changed" { "field": "subject" },
        ),
        SizedBox(height: 16.0),

        // Message field (multiline)
        TextField(
          decoration: {
            labelText: "Message",
            hintText: "Tell us more...",
            border: "outline",
            alignLabelWithHint: true,
          },
          maxLines: 5,
          onChanged: event "field_changed" { "field": "message" },
        ),
        SizedBox(height: 16.0),

        // Terms checkbox
        Row(
          children: [
            Checkbox(
              value: data.agreedToTerms,
              onChanged: event "terms_toggled" {},
            ),
            SizedBox(width: 8.0),
            Expanded(
              child: Text(
                text: "I agree to the Terms of Service and Privacy Policy",
                style: { fontSize: 14.0, color: 0xFF616161 },
              ),
            ),
          ],
        ),
        SizedBox(height: 24.0),

        // Action buttons
        Row(
          mainAxisAlignment: "end",
          children: [
            TextButton(
              onPressed: event "form_cancel" {},
              child: Text(text: "Cancel"),
            ),
            SizedBox(width: 12.0),
            ElevatedButton(
              onPressed: event "form_submit" {},
              child: Padding(
                padding: [16.0, 0.0, 16.0, 0.0],
                child: Text(text: "Send Message"),
              ),
            ),
          ],
        ),
      ],
    ),
  ),
);
```

#### Concepts Demonstrated

1. **Multiple TextFields** - With different configurations
2. **TextField decoration** - labelText, hintText, border, prefixIcon
3. **Keyboard types** - `keyboardType: "emailAddress"`
4. **Multiline input** - `maxLines: 5`
5. **Checkbox** - Bound to `data.agreedToTerms`
6. **Expanded** - For text wrapping in Row
7. **Multiple events** - Different events for different actions
8. **Event parameters** - `{ "field": "name" }` to identify which field changed
9. **Button padding** - Custom padding inside button
10. **Full form layout** - Professional form structure

---

## System Prompt Template for AI Agents

Copy this into your agent's system prompt:

```markdown
## genui_render Tool - RFW Syntax Reference

You have access to the `genui_render` tool for displaying dynamic UI widgets in the chat.

### ⚠️ CRITICAL: RFW is NOT Dart

RFW uses a Dart-like syntax but with different rules. Follow these EXACTLY:

### Syntax Rules

1. **Always start with imports:**
   ```
   import core.widgets;
   import material;
   ```

2. **Enums are STRINGS:**
   - ❌ `mainAxisSize: MainAxisSize.min`
   - ✅ `mainAxisSize: "min"`

3. **Padding is an array [left, top, right, bottom]:**
   - ❌ `padding: EdgeInsets.all(16.0)`
   - ✅ `padding: [16.0, 16.0, 16.0, 16.0]`

4. **Colors are hex integers:**
   - ❌ `color: Colors.blue`
   - ✅ `color: 0xFF2196F3`

5. **TextStyle is a map:**
   - ❌ `style: TextStyle(fontSize: 16.0)`
   - ✅ `style: { fontSize: 16.0 }`

6. **Text requires named parameter:**
   - ❌ `Text("Hello")`
   - ✅ `Text(text: "Hello")`

7. **Events use special syntax:**
   - ✅ `onPressed: event "button_clicked" { "id": "123" }`

8. **Access data with data.fieldName:**
   - ✅ `Text(text: data.userName)`

### Common Colors
- Blue: 0xFF2196F3
- Red: 0xFFE53935
- Green: 0xFF4CAF50
- Grey: 0xFF9E9E9E
- Light Grey: 0xFFF5F5F5
- White: 0xFFFFFFFF
- Black: 0xFF000000

### Template
```
import core.widgets;
import material;

widget MyWidget = Card(
  child: Padding(
    padding: [16.0, 16.0, 16.0, 16.0],
    child: Column(
      mainAxisSize: "min",
      children: [
        Text(text: data.title, style: { fontSize: 18.0, fontWeight: "bold" }),
        SizedBox(height: 8.0),
        Text(text: data.content),
        SizedBox(height: 16.0),
        ElevatedButton(
          onPressed: event "action" {},
          child: Text(text: "OK"),
        ),
      ],
    ),
  ),
);
```
```

---

## Troubleshooting

### Common Errors and Fixes

| Error Message | Cause | Fix |
|---------------|-------|-----|
| `Expected symbol "(" but found .` | Using Dart enum syntax | Change `MainAxisSize.min` to `"min"` |
| `Unknown widget type` | Widget not imported | Add `import core.widgets;` or `import material;` |
| `Expected symbol ":" but found ")"` | Missing named parameter | Change `Text("Hello")` to `Text(text: "Hello")` |
| `Failed to decode widget library` | General syntax error | Check all rules; test incrementally |
| `Unexpected token` | Invalid syntax somewhere | Check for missing commas, brackets, or quotes |
| Widget renders but data is blank | Data access issue | Ensure data is passed and accessed with `data.fieldName` |

### Debugging Steps

1. **Start minimal** - Test with simplest possible widget first
2. **Add incrementally** - Add one element at a time
3. **Check imports** - Ensure both imports are present
4. **Verify data** - Print/log the data parameter to confirm values
5. **Check quotes** - All strings must use double quotes
6. **Check commas** - Each property needs a comma (except last)

---

## Color Reference

### Primary Colors

| Color | Hex Code | Preview |
|-------|----------|---------|
| Red | `0xFFE53935` | 🔴 |
| Pink | `0xFFEC407A` | 🩷 |
| Purple | `0xFFAB47BC` | 🟣 |
| Blue | `0xFF2196F3` | 🔵 |
| Cyan | `0xFF00BCD4` | 🩵 |
| Teal | `0xFF009688` | |
| Green | `0xFF4CAF50` | 🟢 |
| Yellow | `0xFFFFEB3B` | 🟡 |
| Orange | `0xFFFF9800` | 🟠 |
| Brown | `0xFF795548` | 🟤 |

### Neutral Colors

| Color | Hex Code | Usage |
|-------|----------|-------|
| Black | `0xFF000000` | Primary text |
| Dark Grey | `0xFF424242` | Secondary text |
| Grey | `0xFF9E9E9E` | Disabled/hints |
| Light Grey | `0xFFE0E0E0` | Borders |
| Very Light Grey | `0xFFF5F5F5` | Backgrounds |
| White | `0xFFFFFFFF` | Cards/surfaces |

### With Transparency

| Opacity | Alpha Value | Example |
|---------|-------------|---------|
| 100% | `FF` | `0xFF2196F3` |
| 75% | `BF` | `0xBF2196F3` |
| 50% | `80` | `0x802196F3` |
| 25% | `40` | `0x402196F3` |
| 10% | `1A` | `0x1A2196F3` |

---

## Quick Reference Card

```
╔══════════════════════════════════════════════════════════════════╗
║                    RFW QUICK REFERENCE                           ║
╠══════════════════════════════════════════════════════════════════╣
║ IMPORTS (required):                                              ║
║   import core.widgets;                                           ║
║   import material;                                               ║
╠══════════════════════════════════════════════════════════════════╣
║ ENUMS → STRINGS:                                                 ║
║   mainAxisSize: "min" | "max"                                    ║
║   mainAxisAlignment: "start" | "center" | "end" | "spaceBetween" ║
║   crossAxisAlignment: "start" | "center" | "end" | "stretch"     ║
║   fontWeight: "normal" | "bold" | "w100"-"w900"                  ║
╠══════════════════════════════════════════════════════════════════╣
║ PADDING → ARRAY [left, top, right, bottom]:                      ║
║   padding: [16.0, 16.0, 16.0, 16.0]                             ║
╠══════════════════════════════════════════════════════════════════╣
║ COLORS → HEX (0xAARRGGBB):                                       ║
║   color: 0xFF2196F3                                              ║
╠══════════════════════════════════════════════════════════════════╣
║ TEXT:                                                            ║
║   Text(text: "Hello", style: { fontSize: 16.0 })                 ║
╠══════════════════════════════════════════════════════════════════╣
║ EVENTS:                                                          ║
║   onPressed: event "name" { "key": "value" }                     ║
╠══════════════════════════════════════════════════════════════════╣
║ DATA:                                                            ║
║   Text(text: data.fieldName)                                     ║
╚══════════════════════════════════════════════════════════════════╝
```
