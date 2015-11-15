/*******************************************************************************
 * Copyright (c) 2015 itemis AG (http://www.itemis.eu) and others.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *******************************************************************************/
package org.eclipse.xtext.generator.parser.antlr

import com.google.common.io.Files
import com.google.inject.Inject
import java.io.File
import java.nio.charset.Charset
import java.util.List
import org.eclipse.xpand2.XpandExecutionContextImpl
import org.eclipse.xpand2.XpandFacade
import org.eclipse.xtend.lib.annotations.Accessors
import org.eclipse.xtext.Grammar
import org.eclipse.xtext.GrammarUtil
import org.eclipse.xtext.generator.Generator
import org.eclipse.xtext.generator.IFileSystemAccess2
import org.eclipse.xtext.generator.Naming
import org.eclipse.xtext.generator.adapter.FragmentAdapter
import org.eclipse.xtext.generator.parser.antlr.ex.ca.ContentAssistParserGeneratorFragment
import org.eclipse.xtext.generator.parser.antlr.ex.common.AntlrFragmentHelper
import org.eclipse.xtext.generator.parser.antlr.ex.rt.AntlrGeneratorFragment
import org.eclipse.xtext.util.StopWatch
import org.eclipse.xtext.util.internal.Log
import org.eclipse.xtext.xtext.FlattenedGrammarAccess
import org.eclipse.xtext.xtext.RuleFilter
import org.eclipse.xtext.xtext.RuleNames
import org.eclipse.xtext.xtext.generator.Issues
import org.eclipse.xtext.xtext.generator.parser.antlr.ContentAssistGrammarNaming
import org.eclipse.xtext.xtext.generator.parser.antlr.GrammarNaming

/**
 * Compares the ANTLR grammar generated by {@link 
 * org.eclipse.xtext.xtext.generator.parser.antlr.XtextAntlrGeneratorFragment2
 * XtextAntlrGeneratorFragment2} with that of {@link XtextAntlrGeneratorFragment}
 * by running its grammar generation in a temporary folder and calling {@link
 * GrammarComparator} to compare them.
 * 
 * @author Christian Schneider - Initial contribution and API
 * @noreference
 */
 @Log
class XtextAntlrGeneratorComparisonFragment extends FragmentAdapter {

	private static val ENCODING = 'ISO-8859-1'
	
	@Inject
	extension GrammarNaming productionNaming
	
	@Inject
	ContentAssistGrammarNaming contentAssistNaming
	
	@Inject
	AntlrGrammarComparator comparator

	@Accessors
	AntlrOptions options

	@Accessors
	boolean partialParsing;

	@Accessors
	boolean skipContentAssistGrammarComparison = false

	private List<String> advices = newArrayList()

	public def void addRegisterAdvice(String advice) {
		advices += advice;
	}

	static class ErrorHandler implements AntlrGrammarComparator.IErrorHandler {

		private File tmpFolder;

		new(File tmpFolder) {
			this.tmpFolder = tmpFolder
		}

		override handleInvalidGeneratedGrammarFile(AntlrGrammarComparator.ErrorContext context) {
			deleteDir(tmpFolder)
			
			throw new RuntimeException('''
				Noticed an unexpectect character sequence in reference grammar after token �context.testedGrammar.getPreviousToken�
					and before token �context.testedGrammar.getCurrentToken� in line �context.testedGrammar.getLineNumber�
					in file �context.testedGrammar.getAbsoluteFileName�.''')
			}
		
		override handleInvalidReferenceGrammarFile(AntlrGrammarComparator.ErrorContext context) {
			copyFile(context.referenceGrammar.getAbsoluteFileName, context.testedGrammar.getAbsoluteFileName)
			deleteDir(tmpFolder)
			
			throw new RuntimeException('''
				Noticed an unexpectect character sequence in reference grammar after token �context.referenceGrammar.getPreviousToken�
					and before token �context.referenceGrammar.getCurrentToken� in line �context.referenceGrammar.getLineNumber�
					in file �context.referenceGrammar.getAbsoluteFileName�.''')		}
		
		override handleMismatch(String match, String matchReference, AntlrGrammarComparator.ErrorContext context) {
			copyFile(context.referenceGrammar.getAbsoluteFileName, context.testedGrammar.getAbsoluteFileName)
			deleteDir(tmpFolder)
			
			throw new RuntimeException('''
				Generated grammar �context.testedGrammar.getAbsoluteFileName�
					differs at token �match� (line �context.testedGrammar.getLineNumber�), expected token �matchReference� (line �
						context.referenceGrammar.getLineNumber�).''')
		}
	}

	/** 
	 * Deactivate the super class' initialization check.
	 */
	override checkConfiguration(Issues issues) {
	}

	/**
	 * Tweaks the generation of the {@link Generator#SRC_GEN Generator.SRC_GEN} outlet
	 * and injects the {@link #getTmpPath()}.
	 */
	override protected createOutlet(boolean append, String encoding, String name, boolean overwrite, String path) {
		if (name == Generator.SRC_GEN || name == Generator.SRC_GEN_IDE || name == Generator.SRC_GEN_UI) {
			super.createOutlet(append, encoding, name, overwrite, getTmpFolder().absolutePath)			
		} else {			
			super.createOutlet(append, encoding, name, overwrite, path)
		}
	}

	override generate() {
		if (naming === null) {			
			naming = createNaming()
		}
		
		if (options === null) {			
			options = new AntlrOptions
		}
			
		val errorHandler = new ErrorHandler(tmpFolder)
			
		if (projectConfig.runtime?.srcGen != null) {
			projectConfig.runtime.srcGen.loadAndCompareGrammars(Generator.SRC_GEN, errorHandler)
		}
		
		if (!skipContentAssistGrammarComparison && projectConfig.genericIde?.srcGen != null) {
			projectConfig.genericIde.srcGen.loadAndCompareGrammars(Generator.SRC_GEN_IDE, errorHandler)
		}
				
		deleteDir(tmpFolder)
	}


	protected def loadAndCompareGrammars(IFileSystemAccess2 fsa, String outlet, ErrorHandler errorHandler) {
		val stopWatch = new StopWatch()
		stopWatch.reset()
		
		outlet.performXpandBasedGeneration()
		
		var String parserGrammarFileName
		var String lexerGrammarFileName
		var String type
		
		if (outlet == Generator.SRC_GEN) {
			lexerGrammarFileName = productionNaming.getLexerGrammar(grammar).grammarFileName
			parserGrammarFileName = productionNaming.getParserGrammar(grammar).grammarFileName
			type = "runtime"
			
		} else if (outlet == Generator.SRC_GEN_IDE) {
			lexerGrammarFileName = contentAssistNaming.getLexerGrammar(grammar).grammarFileName
			parserGrammarFileName = contentAssistNaming.getParserGrammar(grammar).grammarFileName
			type = "content assist"
			
		} else {
			throw new RuntimeException("Unexpected value of parameter 'outlet'");
		}
		
		val absoluteLexerGrammarFileNameReference = '''�tmpFolder.absolutePath�/�lexerGrammarFileName�'''
		val absoluteParserGrammarFileNameReference = '''�tmpFolder.absolutePath�/�parserGrammarFileName�'''
		
		val resultLexer = if (!grammar.isCombinedGrammar) {
			val lexerGrammarFile = fsa.readTextFile(lexerGrammarFileName)
			val lexerGrammarFileReference = Files.toString(new File(absoluteLexerGrammarFileNameReference), Charset.forName(ENCODING))
			
			comparator.compareGrammars(lexerGrammarFile, lexerGrammarFileReference,
				'''�fsa.path�/�lexerGrammarFileName�''', absoluteLexerGrammarFileNameReference, errorHandler
			)
		}
		
		if (resultLexer != null) {
			LOG.info('''Generated �type� lexer grammar of �resultLexer.testedGrammar.getLineNumber
					� lines matches expected one of �resultLexer.referenceGrammar.getLineNumber�.''')
		}
		
		val grammarFile = fsa.readTextFile(parserGrammarFileName)
		val grammarFileReference = Files.toString(new File(absoluteParserGrammarFileNameReference), Charset.forName(ENCODING))
		
		val result = comparator.compareGrammars(grammarFile, grammarFileReference,
			'''�fsa.path�/�parserGrammarFileName�''', absoluteParserGrammarFileNameReference, errorHandler
		)
		
		LOG.info('''Generated �type� parser grammar of �result.testedGrammar.getLineNumber
				� lines matches expected one of �result.referenceGrammar.getLineNumber� (�stopWatch.reset� ms).''')
	}


	private static class AntlrFragmentHelperEx extends AntlrFragmentHelper {
		
		private Naming naming
		
		new(Naming naming) {
			super(naming)
			this.naming = naming
		}
		
		override getLexerGrammarFileName(Grammar g) {
			return naming.basePackageRuntime(g) + ".parser.antlr.internal.Internal" + GrammarUtil.getSimpleName(g) + "Lexer";
		}
		override getContentAssistLexerGrammarFileName(Grammar g) {
			return naming.basePackageIde(g) + ".contentassist.antlr.internal.Internal" + GrammarUtil.getSimpleName(g) + "Lexer";
		}

	}

	def protected void performXpandBasedGeneration(String outlet) { 
		val RuleFilter filter = new RuleFilter();
		filter.setDiscardUnreachableRules(options.isSkipUnusedRules());
		
		val RuleNames ruleNames = RuleNames.getRuleNames(grammar, true);
		val Grammar flattened = new FlattenedGrammarAccess(ruleNames, filter).getFlattenedGrammar();
		
		val context = createExecutionContext() as XpandExecutionContextImpl;
		
		advices.forEach[
			context.registerAdvices(it);
		];

		val combined = grammar.isCombinedGrammar		
		val helper = if (!combined) new AntlrFragmentHelperEx(naming)
		var String template
		var Object[] params
		
		if (outlet == Generator.SRC_GEN && context.output.getOutlet(Generator.SRC_GEN) != null) {
			
			if (grammar.isCombinedGrammar) {
				template = XtextAntlrGeneratorFragment.name
				params =  #[ options ]
			} else {
				template = AntlrGeneratorFragment.name
				params = #[ options, helper]
			}
			
			XpandFacade.create(context).evaluate2(template.replaceAll("\\.", "::") + "::generate", flattened, params);
			
		} else if (outlet == Generator.SRC_GEN_IDE && context.output.getOutlet(Generator.SRC_GEN_IDE) != null) {
			
			if (grammar.isCombinedGrammar) {
				template = XtextAntlrUiGeneratorFragment.name
				params =  #[ options, partialParsing, naming.hasIde ]
			} else {
				template = ContentAssistParserGeneratorFragment.name
				params = #[ options, helper, partialParsing.booleanValue, naming.hasIde.booleanValue]
			}
			
			XpandFacade.create(context).evaluate2(template.replaceAll("\\.", "::") + "::generate", flattened, params);
		}
	}


	/**
	 * offers a singleton temporary folder 
	 */
	private def File create path: Files.createTempDir() getTmpFolder() {
	}
	
	protected static def copyFile(String from, String to) {
		Files.copy(
			new File(from),
			new File('''�to.substring(0, to.length - 2)�Expected.g''')
		)
	}
	
	/** little helper for cleaning up the temporary stuff. */
    private static def void deleteDir(File dir) {
        if (!dir.exists) {
            return;
        }

        org.eclipse.xtext.util.Files.sweepFolder(dir)
    }
}
