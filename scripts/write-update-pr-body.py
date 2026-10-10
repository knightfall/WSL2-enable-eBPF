#!/usr/bin/env python3
"""Write the validated upstream kernel update's pull-request description."""

import argparse
import os
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path, help='path passed to gh pr create/edit --body-file')
    args = parser.parse_args()
    required = ('KERNEL_TAG', 'KERNEL_COMMIT', 'GITHUB_SERVER_URL',
                'GITHUB_REPOSITORY', 'GITHUB_RUN_ID')
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        parser.error('Missing required environment variables: ' + ', '.join(missing))
    run_url = (f'{os.environ["GITHUB_SERVER_URL"]}/{os.environ["GITHUB_REPOSITORY"]}'
               f'/actions/runs/{os.environ["GITHUB_RUN_ID"]}')
    args.output.write_text(
        f'Update the WSL kernel submodule and source lock to {os.environ["KERNEL_TAG"]} '
        f'({os.environ["KERNEL_COMMIT"]}). The update stays within the existing kernel series.\n\n'
        f'Validation: repository checks and Linux Kconfig resolution passed in [the update run]({run_url}). '
        'Build the kernel and run the documented WSL boot and workload smoke checks before merging.\n'
    )


if __name__ == '__main__':
    main()
