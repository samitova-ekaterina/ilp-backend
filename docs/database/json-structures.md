# JSON structures

A relational database should not turn into a store of documents, and the rubric of the project says so directly: JSON in a relational database is allowed only when its structure is described and justified. This document gives that justification and description for the five `jsonb` columns of the database.

## Why JSON is used at all

ILP recognises 25 kinds of exercises in a PDF and shows them in 32 types, from choosing one option to filling a crossword. What a task consists of differs from type to type: a multiple-choice question has options and the labels of the correct ones, a gap-fill has positions in a sentence and accepted words, a word search has a grid and cells. Three ways of storing this were possible.

| Way | What it would mean | Why it was not chosen |
|---|---|---|
| One wide table with a column for every possible field | Dozens of columns, most of them empty in every row | Nothing would say which columns belong to which type, and every new type would change the table |
| A table per type | About a dozen tables for tasks and as many for answers | Every query for "the tasks of this homework" would join all of them, and a new type would need new tables and new code paths |
| A fixed relational frame and one JSON column for the variable part | The task is a row with its exercise, number, text and page; only the type-dependent body is JSON | Chosen |

So JSON holds only the part that genuinely varies. Everything that is searched, joined or counted stays in ordinary columns with ordinary constraints: which exercise a task belongs to, its type, its topic, its scale, who answered, when, whether the answer was correct.

The design rests on one separation. The **body** describes the content taken from the document; the **type** describes how the learner answers. Because of this the same task can be shown in a harder type without rewriting its body: a gap that the learner first fills by choosing from a bank is later filled by typing, and the body stays as it was.

## The five columns

| Column | Table | What it holds |
|---|---|---|
| `recognition_features` | `core.exercise_type` | How the parser recognises the type in a document: keywords of the instruction, whether a word bank is expected, the layout on the page, the shape of the answer key |
| `body_schema` | `core.exercise_type` | The rule that the three columns below must follow for this type, written in the JSON Schema specification (draft 2020-12) |
| `shared_body` | `core.exercise` | What all tasks of the exercise share: a word bank, names of groups, the right column of pairs, a grid |
| `body` | `core.task` | The parts of one task. Each part has an identifier and, depending on the type, a position in the text, options, a key |
| `content` | `core.answer` | What the learner answered, part by part |

## How the structure is described and checked

The description of the structure is not kept in a separate document that could go out of date. It is data: every row of `core.exercise_type` carries in `body_schema` a JSON Schema with three sections, `shared_body`, `body` and `answer_content`. The application validates a JSON value against the schema of its type before writing it, and the same schema tells a reviewer exactly what a valid value looks like. The test tasks in the repository were validated against these schemas by a program.

JSON Schema was chosen because it is a widely used, published specification with validators for Java, so the rule is written once and is not tied to this project.

The 32 types share 12 schemas, because several types differ in how the learner answers and not in what the task contains.

| Family | Types | The key of a part |
|---|---|---|
| Choice | `single_choice`, `multiple_choice`, `true_false`, `inline_choice`, `single_choice_typed`, `inline_choice_typed`, `multiple_choice_typed` | Labels of the correct options |
| Pairs | `matching`, `matching_typed` | The item of the right column |
| Groups | `grouping`, `grouping_typed` | The group the word belongs to |
| Order | `ordering` | The place in the sequence |
| Gap with a word bank | `gap_bank`, `image_labels_bank`, `gap_bank_typed`, `image_labels_bank_typed` | The word and its accepted variants |
| Place on an image | `hotspot` | An area of the image |
| Typed answer without a bank | `gap_no_bank`, `word`, `image_labels_no_bank`, `table_completion`, `diagram_completion` | The word and its accepted variants |
| Open list | `word_list` | A set of accepted words |
| Correction | `replace_marked`, `find_and_correct` | The fragment and its corrected text |
| Grid | `crossword`, `word_search` | The word and the cells it occupies |
| Composite | `composite`, `composite_reviewed` | Each part has its own kind and key |
| Free answer | `free_text`, `drawing`, `spoken_answer` | No key; a sample answer is possible |

## An example: a gap-fill with a word bank

The exercise shares a bank of words in `exercise.shared_body`:

```json
{"bank": [{"id": "w1", "text": "scarf"}, {"id": "w2", "text": "gloves"}, {"id": "w3", "text": "belt"}, {"id": "w4", "text": "boots"}, {"id": "w5", "text": "slippers"}]}
```

A task with two gaps has two parts in `task.body`. The key is a list: the answer from the document comes first, and further accepted variants may follow. The position is the place of the gap in the text of the task, which is stored in its own column exactly as in the document.

```json
{"parts": [{"id": "g1", "key": ["boots"], "position": 10, "is_example": false}, {"id": "g2", "key": ["slippers"], "position": 46, "is_example": false}]}
```

The answer of a learner in `answer.content` refers to the parts by their identifiers. Here the first gap is right and the second is wrong:

```json
{"parts": [{"id": "g1", "value": "boots"}, {"id": "g2", "value": "scarf"}]}
```

The schema that all three values follow, stored in `exercise_type.body_schema` for the type `gap_bank`:

```json
{
  "type": "object",
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "properties": {
    "body": {
      "type": "object",
      "required": [
        "parts"
      ],
      "properties": {
        "parts": {
          "type": "array",
          "items": {
            "type": "object",
            "required": [
              "id",
              "key",
              "is_example"
            ],
            "properties": {
              "id": {
                "type": "string"
              },
              "key": {
                "type": "array",
                "items": {
                  "type": "string"
                },
                "minItems": 1
              },
              "cell": {
                "type": "object",
                "required": [
                  "row",
                  "column"
                ],
                "properties": {
                  "row": {
                    "type": "integer",
                    "minimum": 0
                  },
                  "column": {
                    "type": "integer",
                    "minimum": 0
                  }
                }
              },
              "anchor": {
                "type": "object",
                "required": [
                  "x",
                  "y"
                ],
                "properties": {
                  "x": {
                    "type": "number",
                    "maximum": 1,
                    "minimum": 0
                  },
                  "y": {
                    "type": "number",
                    "maximum": 1,
                    "minimum": 0
                  }
                }
              },
              "position": {
                "type": "integer",
                "minimum": 0
              },
              "is_example": {
                "type": "boolean"
              },
              "given_letters": {
                "type": "string"
              }
            }
          },
          "minItems": 1
        }
      }
    },
    "shared_body": {
      "type": "object",
      "required": [
        "bank"
      ],
      "properties": {
        "bank": {
          "type": "array",
          "items": {
            "type": "object",
            "required": [
              "id",
              "text"
            ],
            "properties": {
              "id": {
                "type": "string"
              },
              "text": {
                "type": "string"
              }
            }
          },
          "minItems": 1
        }
      }
    },
    "answer_content": {
      "type": "object",
      "required": [
        "parts"
      ],
      "properties": {
        "parts": {
          "type": "array",
          "items": {
            "type": "object",
            "required": [
              "id",
              "value"
            ],
            "properties": {
              "id": {
                "type": "string"
              },
              "value": {
                "type": "string"
              }
            }
          }
        }
      }
    }
  }
}
```

## How the identifier of a part is used outside JSON

The identifier of a part is the one value from inside a JSON body that relational columns refer to, and they do so as plain text: `flag.place_in_task` says which part a flag concerns, and `revision_record.part_id` says which part of a task is scheduled for revision, since only the part answered wrongly comes back. The database does not check that such a part exists in the body, because a constraint cannot look inside another row's JSON; the application takes the identifier from the body it has just validated.

## Recognition features

`recognition_features` is JSON for a different reason: it is a small set of settings read as a whole by the parser and never queried by its fields. Its values come from closed lists.

| Field | Values | Meaning |
|---|---|---|
| `recognizable` | `true`, `false` | Whether the parser looks for this type in a document. Seven types are only ways of showing an exercise that was recognised as another type |
| `base_type` | The code of a type | For a type that is not recognised: the type it is shown from |
| `bank` | `required`, `optional`, `absent` | Whether a word bank is expected |
| `layout` | 17 values such as `text_with_gaps`, `two_columns`, `grid` | How the exercise is laid out on the page |
| `key_shape` | 16 values such as `word_per_gap`, `pairs`, `option_label` | What the answer key looks like |
| `instruction_keywords` | A list of words | Words in the instruction that point to the type |

For the type `gap_bank` the value is:

```json
{"bank": "required", "layout": "text_with_gaps", "key_shape": "word_per_gap", "recognizable": true, "instruction_keywords": ["complete", "fill in", "use the words"]}
```

The keywords are a starting set. They will be refined when the parser is measured on real documents, and each refinement will be an ordinary migration.

## What is deliberately not in JSON

| Kept as an ordinary column | Why |
|---|---|
| The text of a task | It is shown, searched and read aloud; it is the same for every type |
| The result of an answer, the attempt number, the times | They are counted and filtered in almost every query |
| The type shown to the learner (`answer.shown_as_exercise_type_id`) | It is a reference with a foreign key |
| Whether a typo is accepted (`exercise.is_typo_tolerated`) | It is a setting of the author with a default, not part of the content |
| Target words of a task | They are a many-to-many relationship with the dictionary of words |
