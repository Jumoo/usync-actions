"""Regenerates the test fixtures. Run from anywhere: python test/fixtures/make-fixtures.py

Each fixture is a site root with a uSync/v17 folder, so files-verify finds it the
same way it would in a real site. `expected.json` lists the exit codes the tests
assert, keyed by the extra arguments used.
"""
import json
import pathlib
import shutil

HERE = pathlib.Path(__file__).parent
BOM = "﻿"

TEXTSTRING_KEY = "0cc0eba1-9960-42c9-bf9b-60e150b429ae"
ARTICLE_KEY = "a1d1e9b5-6b5d-4c0e-9a40-6f5b3d7c2a11"
HOME_KEY = "c4f2b0aa-1f0e-4f5e-8d1a-2b9f1e0c6d22"
CONTENT_HOME_KEY = "7e3a9c51-0d2b-4b8e-a6f4-91c2d8e5b333"


def usync_config():
    return f'{BOM}<?xml version="1.0" encoding="utf-8"?>\n<uSync version="17.3.6.0" format="10.7.0" />'


def datatype(key, alias, name, editor, ui):
    return f"""{BOM}<?xml version="1.0" encoding="utf-8"?>
<DataType Key="{key}" Alias="{alias}" Level="1">
  <Info>
    <Name>{name}</Name>
    <EditorAlias>{editor}</EditorAlias>
    <EditorUIAlias>{ui}</EditorUIAlias>
  </Info>
  <Config><![CDATA[{{}}]]></Config>
</DataType>"""


def content_type(key, alias, name, allowed=(), description="", tab_key="", prop_key=""):
    structure = "  <Structure />"
    if allowed:
        items = "\n".join(f'    <ContentType Key="{k}" SortOrder="{i}">{a}</ContentType>' for i, (k, a) in enumerate(allowed))
        structure = f"  <Structure>\n{items}\n  </Structure>"
    return f"""{BOM}<?xml version="1.0" encoding="utf-8"?>
<ContentType Key="{key}" Alias="{alias}" Level="1">
  <Info>
    <Name>{name}</Name>
    <Icon>icon-document</Icon>
    <Thumbnail>folder.png</Thumbnail>
    <Description><![CDATA[{description}]]></Description>
    <AllowAtRoot>{"True" if allowed else "False"}</AllowAtRoot>
    <ListView>00000000-0000-0000-0000-000000000000</ListView>
    <Variations>Nothing</Variations>
    <IsElement>false</IsElement>
    <HistoryCleanup>
      <PreventCleanup>False</PreventCleanup>
      <KeepAllVersionsNewerThanDays></KeepAllVersionsNewerThanDays>
      <KeepLatestVersionPerDayForDays></KeepLatestVersionPerDayForDays>
    </HistoryCleanup>
    <Compositions />
    <AllowedTemplates />
  </Info>
{structure}
  <GenericProperties>
    <GenericProperty>
      <Key>{prop_key}</Key>
      <Name>Title</Name>
      <Alias>title</Alias>
      <Definition>{TEXTSTRING_KEY}</Definition>
      <Type>Umbraco.TextBox</Type>
      <Mandatory>false</Mandatory>
      <Validation></Validation>
      <Description><![CDATA[]]></Description>
      <SortOrder>0</SortOrder>
      <Tab Alias="content">Content</Tab>
      <Variations>Nothing</Variations>
      <MandatoryMessage></MandatoryMessage>
      <ValidationRegExpMessage></ValidationRegExpMessage>
      <LabelOnTop>false</LabelOnTop>
    </GenericProperty>
  </GenericProperties>
  <Tabs>
    <Tab>
      <Key>{tab_key}</Key>
      <Caption>Content</Caption>
      <Alias>content</Alias>
      <Type>Tab</Type>
      <SortOrder>0</SortOrder>
    </Tab>
  </Tabs>
</ContentType>"""


def content(key, title):
    return f"""{BOM}<?xml version="1.0" encoding="utf-8"?>
<Content Key="{key}" Alias="Home" Level="1">
  <Info>
    <Parent Key="00000000-0000-0000-0000-000000000000"></Parent>
    <Path>/Home</Path>
    <Trashed>false</Trashed>
    <ContentType>home</ContentType>
    <CreateDate>2026-11-23T12:00:00</CreateDate>
    <NodeName Default="Home" />
    <SortOrder>0</SortOrder>
    <Published Default="true" />
    <Schedule />
    <Template />
  </Info>
  <Properties>
    <title>
      <Value><![CDATA[{title}]]></Value>
    </title>
  </Properties>
</Content>"""


def clean_files():
    return {
        "usync.config": usync_config(),
        "DataTypes/Textstring.config": datatype(TEXTSTRING_KEY, "Textstring", "Textstring", "Umbraco.TextBox", "Umb.PropertyEditorUi.TextBox"),
        "ContentTypes/home.config": content_type(
            HOME_KEY, "home", "Home", allowed=[(ARTICLE_KEY, "article")],
            tab_key="1b7c2f40-8e65-4d3b-9c2a-0a1e5d6f7a01", prop_key="2c8d3a51-9f76-4e4c-8d3b-1b2f6e7a8b02"),
        "ContentTypes/article.config": content_type(
            ARTICLE_KEY, "article", "Article",
            tab_key="3d9e4b62-a087-4f5d-9e4c-2c3a7f8b9c03", prop_key="4eaf5c73-b198-406e-af5d-3d4b8a9cad04"),
    }


CONFLICT = """<<<<<<< HEAD
Our homepage
=======
The homepage
>>>>>>> feature/new-title"""

FIXTURES = {
    # Must pass.
    "clean": ({}, {"": 0, "--content": 0, "--warnings-as-errors": 0}),

    # Two branches each added an `article` content type: same alias, different keys.
    "alias-clash": ({
        "ContentTypes/article_1.config": content_type(
            "9b1f0d84-c2a9-4b7f-b06e-4e5c9bab0e05", "article", "Article",
            tab_key="ac2e1e95-d3ba-4c80-a17f-5f6dacbc1f06", prop_key="bd3f2fa6-e4cb-4d91-b280-6a7ebdcd2a07"),
    }, {"": 1}),

    # A copy of a file under a new name: same key twice.
    "key-clash": ({
        "ContentTypes/article-copy.config": content_type(
            ARTICLE_KEY, "articleCopy", "Article copy",
            tab_key="ce4a3ab7-f5dc-4ea2-a391-7b8fcede3b08", prop_key="df5b4bc8-06ed-4fb3-b4a2-8c9adfef4c09"),
    }, {"": 1}),

    # Merge conflict markers inside a CDATA block: still valid XML, so only a raw text scan finds them.
    "conflict-markers": ({
        "ContentTypes/article.config": content_type(
            ARTICLE_KEY, "article", "Article", description=CONFLICT,
            tab_key="3d9e4b62-a087-4f5d-9e4c-2c3a7f8b9c03", prop_key="4eaf5c73-b198-406e-af5d-3d4b8a9cad04"),
    }, {"": 1}),

    # Not XML at all any more.
    "invalid-xml": ({
        "DataTypes/Textstring.config": datatype(TEXTSTRING_KEY, "Textstring", "Textstring", "Umbraco.TextBox", "Umb.PropertyEditorUi.TextBox").replace("</DataType>", ""),
    }, {"": 1}),

    # A delete marker for a key that a live file still uses.
    "delete-clash": ({
        "ContentTypes/article_deleted.config": f'{BOM}<?xml version="1.0" encoding="utf-8"?>\n<Empty Key="{ARTICLE_KEY}" Alias="article" Change="Delete" />',
    }, {"": 1}),

    # Content is skipped unless --content is given.
    "content-conflict": ({
        "Content/home.config": content(CONTENT_HOME_KEY, CONFLICT),
    }, {"": 0, "--content": 1}),
}


def main():
    for name, (overrides, expected) in FIXTURES.items():
        root = HERE / name
        if root.exists():
            shutil.rmtree(root)
        files = clean_files()
        files.update(overrides)
        for rel, text in files.items():
            path = root / "uSync" / "v17" / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8", newline="\n")
        (root / "expected.json").write_text(json.dumps(expected, indent=2) + "\n", encoding="utf-8", newline="\n")
        print(f"{name}: {len(files)} files, expects {expected}")


if __name__ == "__main__":
    main()
