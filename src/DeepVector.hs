{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DataKinds #-}

-- {-# OPTIONS_GHC -Wincomplete-patterns #-}

module DeepVector
  where

import           Data.Monoid

import           Data.Functor.Rep
import           Data.Functor.Identity

import           Data.Nat
import           Data.Type.Nat
import           Data.Vec.Lazy
import qualified Data.Vec.Lazy as Vec


class Basis v a where
  type Dim v a :: Nat

  stdBasis :: Vec (Dim v a) (v a)
  stdBasis = fmap snd (toStdBasis ZeroVec)
  toStdBasis :: DeepVector v a -> Vec (Dim v a) (a, v a)

basisRepToVector :: Vec (Dim v a) (a, v a) -> DeepVector v a
basisRepToVector = Vec.foldr (:+) ZeroVec . fmap (uncurry (:*))

data Scaled v a where
  (:*) :: a -> v a -> Scaled v a

infixr 9 :*

deriving instance (Show a, Show (v a)) => Show (Scaled v a)

-- | A deep embedding of linear combinations in a vector space generated by
-- the type (v a)
data DeepVector v a where
  ZeroVec :: DeepVector v a
  (:+) :: Scaled v a -> DeepVector v a -> DeepVector v a

infixr 8 :+

type LinearTrans u v a = v a -> u a

appLinearTrans :: LinearTrans u v a -> DeepVector v a -> DeepVector u a
appLinearTrans t ZeroVec       = ZeroVec -- The zero vector always maps to the zero vector
appLinearTrans t (s :* u :+ v) = s :* (t u) :+ appLinearTrans t v

data Void1 a

type TrivialSpace = DeepVector Void1

deriving instance (Show a, Show (v a)) => Show (DeepVector v a)

instance Semigroup (DeepVector v a) where
  u <> ZeroVec = u
  ZeroVec <> v = v
  (s :* u :+ v) <> w = s :* u :+ (v <> w)

instance Monoid (DeepVector v a) where
  mempty = ZeroVec

class Algebra f a where
  algebra :: f a -> f a -> f a

data UnitTerm1 a where
  UnitTerm1 :: Int -> UnitTerm1 a

deriving instance (Show a) => Show (UnitTerm1 a)

data Polynomial1 a where
  Polynomial1 :: DeepVector UnitTerm1 a -> Polynomial1 a

deriving instance (Show a) => Show (Polynomial1 a)

evalPoly1 :: Num a => a -> Polynomial1 a -> a
evalPoly1 _v (Polynomial1 ZeroVec) = 0
evalPoly1  v (Polynomial1 (s :* UnitTerm1 ex :+ q)) =
  (s * (v ^ ex)) + evalPoly1 v (Polynomial1 q)

--
-- Projective spaces --
--

data Projective v a = Projective a (v a) -- Increase the dimension by 1

type ProjSpace v = DeepVector (Projective v)

instance forall v a. (Monoid (v a), Basis v a, Num a) => Basis (Projective v) a where
  type Dim (Projective v) a = S (Dim v a)

  toStdBasis origV = (projCoord, Projective 1 mempty) ::: (fmap (\(coeff, v) -> (coeff, Projective 0 v)) (toStdBasis underlying))
    where
      underlying = projectiveUnderlying origV
      projCoord  = projectiveCoordinate origV

-- | Recover the original underyling space (effectively map snd)
projectiveUnderlying :: ProjSpace v a -> DeepVector v a
projectiveUnderlying ZeroVec = ZeroVec
projectiveUnderlying (s :* (Projective _ u) :+ v) = (s :* u) :+ projectiveUnderlying v

projectiveCoordinate :: Num a => ProjSpace v a -> a
projectiveCoordinate ZeroVec = 0
projectiveCoordinate (s :* (Projective c _) :+ v) = (s * c) + projectiveCoordinate v

-- TODO: Is this right?
toProjective :: Num a => DeepVector v a -> ProjSpace v a
toProjective = appLinearTrans (Projective 1)

-- | Projective transformation (technically required to be an isomorphism)
type Homography u v a = Projective u a -> Projective v a

appHomographyUnderlying :: (Functor v, Fractional a) => Homography u v a -> DeepVector u a -> DeepVector v a
appHomographyUnderlying t = appHomography t . toProjective

appHomography :: (Functor v, Fractional a) => Homography u v a -> ProjSpace u a -> DeepVector v a
appHomography t origU = appLinearTrans go (projectiveUnderlying projV)
  where
    projV = appLinearTrans t origU
    projCoord = projectiveCoordinate projV

    go v = fmap (/projCoord) v

stereographicProj :: forall v a. (Functor v, Fractional a) => ProjSpace v a -> DeepVector v a
stereographicProj = appHomography go
  where
    go :: Homography v v a
    go (Projective z v) = Projective (1-z) v

hemisphereProj :: forall v a. (Functor v, Fractional a) => ProjSpace v a -> DeepVector v a
hemisphereProj = projectiveUnderlying

inverseStereographicProj :: forall v a. (Monoid (v a), Functor v, Basis v a, Fractional a) => DeepVector v a -> ProjSpace v a
inverseStereographicProj origV = (x0 :* Projective 1 mempty) :+ (appLinearTrans (Projective 0) xRest)
  where
    stdBasisV = toStdBasis origV

    sSqr :: a
    sSqr = Vec.sum $ fmap ((^2) . fst) stdBasisV

    x0 = (sSqr - 1) / (sSqr + 1)

    xRest = basisRepToVector (fmap (\(coeff, basisVec) -> ((2*coeff)/(sSqr + 1), basisVec)) stdBasisV)

-- TODO: Test
stereographicFisheye :: forall v a. (Monoid (v a), Functor v, Basis v a, Fractional a) => DeepVector v a -> DeepVector v a
stereographicFisheye = hemisphereProj . inverseStereographicProj



-- | Quadratic forms
data QuadFormVars vars a = QuadFormVars vars vars

type QuadForm vars = DeepVector (QuadFormVars vars)

data Vars3 = X3 | Y3 | Z3


data Trig a where
  TrigConst :: Trig a
  Sin :: Trig a
  Cos :: Trig a
  Tan :: Trig a
  ASin :: Trig a
  ACos :: Trig a
  ATan :: Trig a

-- Linear combinations of trig functions (includes constant terms)
type TrigSpace = DeepVector Trig



data Field a where
  FieldElem :: a -> Field a

  FieldAdd :: Field a -> Field a -> Field a
  FieldNeg :: Field a -> Field a
  FieldMul :: Field a -> Field a -> Field a
  FieldDiv :: Field a -> Field a -> Field a

  FieldZero :: Field a
  FieldOne  :: Field a


data V2 a = V2 a a deriving (Functor)

instance forall a. Num a => Semigroup (V2 a) where
  V2 x y <> V2 x' y' = V2 (x+x') (y+y')

instance forall a. Num a => Monoid (V2 a) where
  mempty = V2 0 0

instance forall a. Num a => Basis V2 a where
  type Dim V2 a = Nat2

  stdBasis = V2 1 0 ::: V2 0 1 ::: VNil

  toStdBasis origV = (x, V2 1 0) ::: (y, V2 0 1) ::: VNil
    where
      V2 x y = eval origV

      eval :: DeepVector V2 a -> V2 a
      eval ZeroVec = V2 0 0
      eval (s :* u :+ v) = (fmap (s*) u) <> eval v

