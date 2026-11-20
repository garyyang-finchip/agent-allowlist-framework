# Filing with the ERCs repository

The specification is filed as a pull request against `ethereum/ERCs`. The pull request contains the specification and its assets and nothing else. Until an editor assigns a number, the files carry the placeholder number 9999.

## What is filed

`python3 scripts/make-filing-package.py` checks the specification against the files it quotes and writes the package to `ercs-pr-package/`:

| Path in the ERCs repository | Content | Files |
| --- | --- | --- |
| `ERCS/erc-9999.md` | The specification | 1 |
| `assets/erc-9999/contracts/` | Reference implementation: `AWFRegistry.sol`, `AWFGuard.sol`, `Introspection.sol` | 3 |
| `assets/erc-9999/contracts/interfaces/` | Types and the five interfaces | 6 |
| `assets/erc-9999/contracts/adapters/` | The two example modules | 2 |
| `assets/erc-9999/contracts/examples/` | The example consumer | 1 |
| `assets/erc-9999/schemas/` | JSON Schemas of the documents and the vocabulary of dimensions | 8 |
| `assets/erc-9999/examples/` | Documents of the worked cases | 19 |
| `assets/erc-9999/vectors/` | Test vectors | 5 |

Forty-five files. Tests, scripts and tools stay in this repository and are not filed.

The script refuses to write the package when an interface quoted in the specification differs from its file, when a quoted identifier or hash is in no vector file, when a table worked out in the text differs from the rule, when an asset is not linked or a link does not resolve, when the text has a form the ERCs validator rejects, or when a file is empty or not plain ASCII.

## Order of steps

1. **Repository.** Create `github.com/garyyang-finchip/agent-whitelist-framework` and upload this package. It has no dotfiles in subdirectories; the one dotfile is `.gitignore` at the root. Shell and Python scripts are run as `bash scripts/<name>.sh` and `python3 scripts/<name>.py`, so they need no executable bit.
2. **Discussion topic.** Open the topic on Ethereum Magicians in the category ERCs with the text of [magicians-post.md](magicians-post.md).
3. **Discussion link.** Run `python3 scripts/make-filing-package.py --discussions-to <link of the topic>`. The package then carries the link. Put the same link on the `discussions-to` line of `ERCS/erc-9999.md` in this repository.
4. **Branch, from upstream.** The branch is cut from `ethereum/ERCs` `master`, not from the `master` of the fork, and the fork's `master` is left as it is:
    1. Open `https://github.com/ethereum/ERCs/tree/master/ERCS`, choose Add file, Create new file.
    2. Name the file `erc-9999.md` (the path shown has to read `ERCs/ERCS/erc-9999.md`) and paste the content of `ercs-pr-package/ERCS/erc-9999.md`.
    3. Choose Commit changes, then Propose changes, with the message `Add ERC: Agent Whitelist Framework`. GitHub creates a branch `patch-<n>` in the fork from the upstream `master`. Do not open the pull request yet.
    4. In the fork, rename that branch to `add-erc-agent-whitelist`.
5. **Upload the assets.** In that branch of the fork choose Add file, Upload files, and drop the folder `assets` from `ercs-pr-package/`. Commit to the branch with the message `Add ERC: Agent Whitelist Framework`.
6. **Check the branch.** `https://github.com/ethereum/ERCs/compare/master...garyyang-finchip:ERCs:add-erc-agent-whitelist` has to show 45 changed files, all of them `ERCS/erc-9999.md` or under `assets/erc-9999/`.
7. **Pull request.** Open a pull request from the branch to `ethereum/ERCs` `master`.

    Title:

    ```text
    Add ERC: Agent Whitelist Framework
    ```

    Description:

    ```text
    Adds a draft ERC, Agent Whitelist Framework (AWF): scoped allow and deny lists
    for agents and other objects, with stated grounds, adoption by consumers and
    uniform results.

    - Specification: ERCS/erc-9999.md (placeholder number)
    - Assets: interfaces and reference implementation, two example modules,
      JSON Schemas of the documents, example documents and test vectors
    - Discussion: <link of the topic>
    - Reference repository with tests:
      https://github.com/garyyang-finchip/agent-whitelist-framework
    ```

8. **Checks.** The pull request runs the ERCs validator, the Markdown linter, the spell checker and the link checker. The specification passes the first three locally with the configuration of the ERCs repository; the link checker needs the pull request itself.
9. **After the pull request exists.** Add its link to the first post of the discussion topic, to the README and to [magicians-post.md](magicians-post.md).

## When the number is assigned

An editor assigns the number in a review comment on the specification file.

1. Run `python3 scripts/make-filing-package.py --number <N> --discussions-to <link>`.
2. In the pull request branch, delete `ERCS/erc-9999.md` and `assets/erc-9999/` and upload `ERCS/erc-<N>.md` and `assets/erc-<N>/` from the regenerated package.
3. Rename the discussion topic to `ERC-<N>: Agent Whitelist Framework`.
4. When the checks are green, answer inside the editor's review conversation and resolve it.
5. In this repository, rename `ERCS/erc-9999.md` and `assets/erc-9999/` to the assigned number and replace `erc-9999` and `eip-9999` in the paths used by `foundry.toml`, the tests, the script, the scripts and the tools. Identifiers and vectors do not depend on the number, so on-chain evidence stays valid.

## After the merge

The specification is then a Draft in the ERCs repository. Later changes are filed as pull requests titled `Update ERC-<N>: <what changes>` from the same fork.
