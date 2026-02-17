import { execaCommand } from "execa";

const PREVIEW_BIN = "/run/current-system/sw/bin/preview";

export function prToSlug(_repoName: string, prNumber: number): string {
  return `${prNumber}`;
}

async function runPreview(args: string): Promise<void> {
  console.log(`[preview] Running: ${PREVIEW_BIN} ${args}`);
  try {
    const { stdout, stderr } = await execaCommand(`${PREVIEW_BIN} ${args}`, {
      timeout: 1_200_000, // 20 minute timeout for builds (vertex/Elixir can be slow)
    });
    if (stdout) console.log(`[preview] stdout: ${stdout}`);
    if (stderr) console.log(`[preview] stderr: ${stderr}`);
  } catch (error) {
    console.error(`[preview] Command failed: preview ${args}`, error);
    throw error;
  }
}

export async function createPreview(
  repo: string,
  branch: string,
  slug: string,
  type: string = "node"
): Promise<void> {
  const typeFlag = type !== "node" ? ` --type ${type}` : "";
  await runPreview(`create ${repo} ${branch} --slug ${slug}${typeFlag}`);
}

export async function updatePreview(slug: string): Promise<void> {
  await runPreview(`update ${slug}`);
}

export async function destroyPreview(slug: string): Promise<void> {
  await runPreview(`destroy ${slug}`);
}

export async function postPRComment(
  repo: string,
  prNumber: number,
  body: string
): Promise<void> {
  console.log(`[preview] Posting comment on ${repo}#${prNumber}`);
  try {
    await execaCommand(
      `/run/current-system/sw/bin/gh pr comment ${prNumber} --repo ${repo} --body "${body.replace(/"/g, '\\"')}"`,
      { timeout: 30_000 }
    );
  } catch (error) {
    console.error(`[preview] Failed to post PR comment:`, error);
  }
}
