import { buildSystemPrompt } from './buildSystemPrompt';

/**
 * JAOS (Jarvis Autonomous Operating System) Prompt Library
 * 
 * This file serves as the entry point for the modular prompt engine.
 * Individual logic modules are located in the same directory.
 */

export const getJarvisSystemPrompt = (jaosIdentity, jaosState, hangingTxt, eventsTxt, coreMemory, psychProfile, now) => {
  return buildSystemPrompt(jaosIdentity, jaosState, hangingTxt, eventsTxt, coreMemory, psychProfile, now);
};

export const OCR_CLEANING_PROMPT = `You are a strict data-cleaning algorithm. I will give you raw OCR text from an image that may contain typos and spelling errors. Your ONLY job is to output the corrected, highly accurate version of the text. Do not converse. Do not add intro or outro words. Just output the cleaned payload text.`;
