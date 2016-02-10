----------------------------------------------------------------- POD -----------------------------------------------------------------
Name:
{name|template}

Class name and inheritance:
{join inheritance}{join.}{join}

Synopsis:
{synopsis|template}

Description:
{description|template}

{foreach descriptionItems} - {foreach.name}: {foreach.description|template}

{foreach}

Methods:
{foreach methodsItems} - {foreach.name}: {foreach.description|template}

{foreach}

Author:
{author|template}

License:
{license|template}
----------------------------------------------------------------- END -----------------------------------------------------------------{separator inheritance} -> {separator}{template text}{template.}{template}{template code-block}<pre>{template.}</pre>{template}{template code}<code>{template.}</code>{template}{template bold}<strong>{template.}</strong>{template}{template italic}<em>{template.}</em>{template}{template underline}<u>{template.}</u>{template}{template link}<a>{template.}</a>{template}