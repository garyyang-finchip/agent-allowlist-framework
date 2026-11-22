# Filing with the ERCs repository

The specification is filed with `ethereum/ERCs` as ERC-8507.

| | |
| --- | --- |
| Pull request | [ethereum/ERCs#2192](https://github.com/ethereum/ERCs/pull/2192), from the branch `add-erc-agent-whitelist` of the fork `garyyang-finchip/ERCs` |
| Number | 8507, assigned by an editor on 2026-11-21 in a review comment on the specification file |
| Title | Agent Allowlist Framework, as the same editor suggested; the pull request was opened as "Add ERC: Agent Whitelist Framework" |
| Short name | AAF. Interfaces, contracts, tags, schema files and this repository were renamed with the title; they carried AWF and `agent-whitelist-framework` before |
| Discussion | [Ethereum Magicians, topic 30456](https://ethereum-magicians.org/t/erc-8507-agent-allowlist-framework-aaf/30456) |

## What is filed

`python3 scripts/make-filing-package.py` checks the specification against the files it quotes and writes the package to `ercs-pr-package/`. That directory is generated and is not kept in this repository.

| Path in the ERCs repository | Content | Files |
| --- | --- | --- |
| `ERCS/erc-8507.md` | The specification | 1 |
| `assets/erc-8507/contracts/` | Reference implementation: `AAFRegistry.sol`, `AAFGuard.sol`, `Introspection.sol` | 3 |
| `assets/erc-8507/contracts/interfaces/` | Types and the five interfaces | 6 |
| `assets/erc-8507/contracts/adapters/` | The two example modules | 2 |
| `assets/erc-8507/contracts/examples/` | The example consumer | 1 |
| `assets/erc-8507/schemas/` | JSON Schemas of the documents and the vocabulary of dimensions | 8 |
| `assets/erc-8507/examples/` | Documents of the worked cases | 19 |
| `assets/erc-8507/vectors/` | Test vectors | 5 |

Forty-five files. Tests, scripts and tools stay in this repository and are not filed.

The script refuses to write the package when an interface quoted in the specification differs from its file, when a quoted identifier or hash is in no vector file, when a table worked out in the text differs from the rule, when an asset is not linked or a link does not resolve, when the text has a form the ERCs validator rejects, or when a file is empty or not plain ASCII.

In the text of the specification, links to assets are written `../assets/eip-8507/...` although the directory is `assets/erc-8507/`: the site of the ERCs repository is built with that name.

## Replacing the placeholder in the pull request branch

The branch carried `ERCS/erc-9999.md` and `assets/erc-9999/`. The numbered files replace them in three commits, in this order, so that the branch never holds both sets:

1. In the branch `add-erc-agent-whitelist` of the fork, open the folder `assets/erc-9999`, choose Delete directory and commit to the branch.
2. Open `ERCS/erc-9999.md`, choose Delete file and commit to the branch.
3. At the root of the branch choose Add file, Upload files, and drop the two folders `ERCS` and `assets` of the package together. Commit to the branch.
4. Check `https://github.com/ethereum/ERCs/compare/master...garyyang-finchip:ERCs:add-erc-agent-whitelist`: 45 changed files, all of them `ERCS/erc-8507.md` or under `assets/erc-8507/`, none with 9999 in its path.
5. Change the title of the pull request to `Add ERC: Agent Allowlist Framework` and replace the placeholder path in its description.
6. Rename the discussion topic to `ERC-8507: Agent Allowlist Framework (AAF)`.
7. When the checks are green, answer inside each of the editor's two review conversations and resolve it.

The pull request runs the ERCs validator, the Markdown linter, the spell checker and the link checkers. The specification passes the first three locally with the configuration of the ERCs repository.

## The branch keeps its name

The branch `add-erc-agent-whitelist` is not renamed. Renaming the head branch of an open pull request closes the pull request, and the number 8507 was assigned in this one. The branch is deleted after the merge, and later branches are named after the new title.

## The fork

The branch was cut from `ethereum/ERCs` `master` through Create new file and Propose changes on the upstream repository, not from the `master` of the fork, which is left as it is. Later branches are cut the same way.

## After the merge

The specification is then a Draft in the ERCs repository. Later changes are filed as pull requests titled `Update ERC-8507: <what changes>` from a new branch of the same fork, with the files of a freshly written package.
