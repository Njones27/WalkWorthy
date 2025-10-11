import {
  runVerseSelectionAgent,
  AgentRunInput,
  VerseSelectionResult,
} from './walkworthy-agent';

export interface AgentPickInput extends AgentRunInput {}

export interface AgentPickResult extends VerseSelectionResult {}

export async function pickVerseWithAgentKit(input: AgentPickInput): Promise<AgentPickResult> {
  return runVerseSelectionAgent({
    profile: input.profile,
    stressfulItems: input.stressfulItems,
    verseCandidates: input.verseCandidates,
    translationPreference: input.translationPreference ?? 'ESV',
  });
}
