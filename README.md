# GitHub documentation builder with Retype

This builds a static website using retype and pushes to the root of the **gh-pages** or another (specified) branch.

See more about Retype at: [Retype website](https://retype.com/)

:::
The target branch will have all files removed and a fresh build pushed in. While this should result just in the minimal diff when rebuilding the documentation, if non-related files are in the branch, they will be removed. The **CNAME** file, if present, will be preserved.
:::

## What's new

- Compatible with the latest GitHub-hosted runner host platforms (**windows-latest**, **ubuntu-latest**, **macos-latest**)
- Pushes built website to any branch on root directory. Defaults to **gh-pages**.
- Allows to specify repository root to search for **input documentation files**.
- Allows not pushing back to GitHub, useful for testing and manually publishing the compiled website.
- If the target branch already exists, will create an unique name based on the workflow run ID, run count and a number to ensure uniqueness. This branch can then be merged or pull-requested.
- Ability to overwrite target branch instead of creating new branch. Useful for stable unattended updates.

## Usage

See [action.yml](action.yml)

### Simplest config

Will compile documentation off any **.md** file in the repository and push to the **gh-pages** branch, creating a new branch to allow review if it already exists. The project name will be **<repository_owner>/<repository_name>**.

```yaml
steps:
- uses: actions/checkout@v2

- uses: retypeapp/action@main
```

### Specify project name
```yaml
steps:
- uses: actions/checkout@v2

- uses: retypeapp/action@main
  with:
    project-name: "My Open Source project"
```

### Push to specific branch
```yaml
steps:
- uses: actions/checkout@v2

- uses: retypeapp/action@main
  with:
    branch: "my-website-is-here"
```

### Do not push anything back to GitHub
```yaml
steps:
- uses: actions/checkout@v2

- uses: retypeapp/action@main
  with:
    no-push-back: true
```

### Update branch if documentation already exists
```yaml
steps:
- uses: actions/checkout@v2

- uses: retypeapp/action@main
  with:
    overwrite-branch: true
```

:::warning
This will wipe the branch and add a fresh built website version, so besides the **CNAME** file, any other existing files that are not generated by Retype will be removed!
:::

## Limitations

### Pushes files only to root of repo branches

:exclamation: At this point we do not support specifying a target subfolder within a branch, so that branch will be wiped and fresh documentation always placed at its root directory.

### No check for target branch

:exclamation: If you specify the default branch and `overwrite-branch: true`, the branch will be replaced with the documentation files. This can easily be undone by resetting the branch's `HEAD` to a previous commit where the files are still intact.

### No access to files after step done

:exclamation: Once the Retype Action step is done, the target temporary directory where the website is built will not be available to next steps, but the files will be available at a clean version of the repository's root and they can be then manually published.

## Additional Documentation

See [Quickstart for GitHub Actions](https://docs.github.com/en/actions/quickstart) for basic information on creating GitHub Actions.

See [Retype's Getting Started guide](https://retype.com/getting_started/) for more information on how to use Retype.

# License

The scripts and documentation in this project are released under the [Apache 2.0 License](LICENSE)

Retype is licensed under the [Retype Software License Agreement](https://retype.com/LICENSE/)