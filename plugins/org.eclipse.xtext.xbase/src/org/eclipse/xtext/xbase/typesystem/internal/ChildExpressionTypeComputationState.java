/*******************************************************************************
 * Copyright (c) 2012 itemis AG (http://www.itemis.eu) and others.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *******************************************************************************/
package org.eclipse.xtext.xbase.typesystem.internal;

import org.eclipse.jdt.annotation.NonNullByDefault;
import org.eclipse.xtext.common.types.JvmTypeReference;
import org.eclipse.xtext.xbase.XExpression;
import org.eclipse.xtext.xbase.scoping.batch.IFeatureScopeSession;
import org.eclipse.xtext.xbase.typesystem.computation.ConformanceHint;

/**
 * @author Sebastian Zarnekow - Initial contribution and API
 * TODO JavaDoc, toString
 */
@NonNullByDefault
public class ChildExpressionTypeComputationState extends ExpressionTypeComputationState {

	protected ChildExpressionTypeComputationState(ResolvedTypes resolvedTypes,
			IFeatureScopeSession featureScopeSession,
			DefaultReentrantTypeResolver reentrantTypeResolver, 
			ExpressionTypeComputationState parent,
			XExpression expression) {
		super(resolvedTypes, featureScopeSession, reentrantTypeResolver, parent, expression);
	}
	
	@Override
	protected ExpressionTypeComputationState getParent() {
		return (ExpressionTypeComputationState) super.getParent();
	}
	
	@Override
	protected JvmTypeReference acceptType(AbstractTypeExpectation expectation, JvmTypeReference type,
			ConformanceHint conformanceHint, boolean returnType) {
		JvmTypeReference actualType = super.acceptType(expectation, type, conformanceHint, returnType);
		getResolvedTypes().acceptType(getParent().getExpression(), expectation, actualType, conformanceHint, returnType);
		return actualType;
	}
}
